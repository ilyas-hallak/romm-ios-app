import Testing
import Foundation
@testable import romm

/// Keeps the ROM library inside the test's temporary folder and records the
/// metadata the finalizer stores.
private final class CoordinatorROMs: PLocalROMRepository, @unchecked Sendable {
    let romsBaseURL: URL
    var saved: [DownloadedROM] = []

    init(romsBaseURL: URL) {
        self.romsBaseURL = romsBaseURL
    }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { saved }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { saved.first { $0.id == id } }
    func saveDownloadedROM(_ rom: DownloadedROM) throws { saved.append(rom) }
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { saved.count }
}

/// Stands in for the device volume and remembers the figure it was asked about,
/// which is how the reserved bytes of other jobs become observable.
private final class CoordinatorStorageProbe: PDeviceStorageProbe, @unchecked Sendable {
    var availableBytes: Int64
    var requestedBytes: Int64?

    init(availableBytes: Int64) {
        self.availableBytes = availableBytes
    }

    func checkStorage(forAdditionalBytes bytes: Int64) async -> (fits: Bool, availableBytes: Int64) {
        requestedBytes = bytes
        return (fits: availableBytes >= bytes, availableBytes: availableBytes)
    }
}

/// Hands out a request for any download path, so the path the coordinator built
/// can be read back off the started transfer.
private final class StubDownloadRequestClient: StubRommAPIClient {
    override func makeDownloadRequest(path: String) throws -> URLRequest {
        URLRequest(url: URL(string: "https://romm.invalid/\(path)")!)
    }
}

/// Prepares a destination the coordinator could not have worked out itself, and
/// keeps the destinations it was handed when jobs were finished.
private final class RelocatingFinalizer: PROMDownloadFinalizer, @unchecked Sendable {
    let relativePath: String
    let directoryURL: URL
    private(set) var finishedDestinations: [ROMDownloadDestination] = []

    init(relativePath: String, directoryURL: URL) {
        self.relativePath = relativePath
        self.directoryURL = directoryURL
    }

    func prepare(rom: Rom, files: [RomFileInfo], reservedBytes: Int64) async throws -> ROMDownloadDestination {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return ROMDownloadDestination(
            relativePath: relativePath,
            directoryURL: directoryURL,
            didCreateDirectory: true,
            ownedFileNames: files.map(\.fileName)
        )
    }

    func validateTransferredFile(
        named fileName: String,
        expectedSize: Int64,
        in destination: ROMDownloadDestination
    ) throws -> DownloadedROMFile {
        DownloadedROMFile(fileName: fileName, fileSizeBytes: expectedSize)
    }

    func finish(rom: Rom, files: [RomFileInfo], destination: ROMDownloadDestination) throws -> DownloadedROM {
        finishedDestinations.append(destination)
        return try writeMetadata(
            rom: rom,
            destination: destination,
            validatedFiles: files.map { DownloadedROMFile(fileName: $0.fileName, fileSizeBytes: $0.fileSizeBytes) }
        )
    }

    func writeMetadata(
        rom: Rom,
        destination: ROMDownloadDestination,
        validatedFiles: [DownloadedROMFile]
    ) throws -> DownloadedROM {
        DownloadedROM(
            id: rom.id,
            name: rom.name,
            platformName: rom.platform?.name ?? "",
            platformSlug: rom.platformSlug ?? "",
            downloadedAt: Date(),
            totalSizeBytes: validatedFiles.reduce(0) { $0 + $1.fileSizeBytes },
            localDirectory: destination.relativePath,
            files: validatedFiles,
            urlCover: rom.urlCover
        )
    }

    func cleanUp(_ destination: ROMDownloadDestination) {}
}

@MainActor
struct DownloadJobCoordinatorTests {

    // MARK: - Fixture

    private struct Fixture {
        let root: URL
        let romsBaseURL: URL
        let store: DownloadJobStore
        let client: FakeBackgroundTransferClient
        let repository: CoordinatorROMs
        let probe: CoordinatorStorageProbe
        let coordinator: DownloadJobCoordinator

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        var romDirectory: URL {
            romsBaseURL.appendingPathComponent("gb/Pokemon Red")
        }
    }

    private func makeFixture(availableBytes: Int64 = 10_000_000, store: DownloadJobStore? = nil, root: URL? = nil) -> Fixture {
        let root = root ?? makeRoot()
        let romsBaseURL = root.appendingPathComponent("ROMs", isDirectory: true)
        try? FileManager.default.createDirectory(at: romsBaseURL, withIntermediateDirectories: true)
        let store = store ?? DownloadJobStore(rootDirectory: root.appendingPathComponent("queue", isDirectory: true))
        let repository = CoordinatorROMs(romsBaseURL: romsBaseURL)
        let probe = CoordinatorStorageProbe(availableBytes: availableBytes)
        let client = FakeBackgroundTransferClient()
        let coordinator = DownloadJobCoordinator(
            transferClient: client,
            store: store,
            finalizer: ROMDownloadFinalizer(repository: repository, storageProbe: probe),
            apiClient: StubDownloadRequestClient(),
            romRepository: repository
        )
        return Fixture(
            root: root,
            romsBaseURL: romsBaseURL,
            store: store,
            client: client,
            repository: repository,
            probe: probe,
            coordinator: coordinator
        )
    }

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadJobCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func rom(id: Int = 7, name: String = "Pokemon Red") -> Rom {
        Rom(id: id, name: name, platformId: 3, urlCover: nil, platformSlug: "gb")
    }

    private func file(_ name: String, _ size: Int64) -> RomFileInfo {
        RomFileInfo(
            id: name,
            fileName: name,
            fileSizeBytes: size,
            fileExtension: (name as NSString).pathExtension
        )
    }

    private func write(_ name: String, bytes: Int, in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(repeating: 0xAB, count: bytes).write(to: directory.appendingPathComponent(name))
    }

    /// A job as an earlier app session would have left it behind: transferring,
    /// with no destination prepared in this session.
    private func seedJob(
        in store: PDownloadJobStore,
        state: DownloadJobState = .running,
        fileState: DownloadJobFileState = .running,
        restartCount: Int = 0
    ) -> DownloadJob {
        let job = DownloadJob(
            romId: 7,
            rom: DownloadJobRomSnapshot(id: 7, name: "Pokemon Red", platformId: 3, platformSlug: "gb"),
            platformName: "gb",
            romDirectoryPath: "gb/Pokemon Red",
            state: state,
            files: [
                DownloadJobFile(
                    fileName: "red.gb",
                    expectedSizeBytes: 10,
                    state: fileState,
                    receivedBytes: 4
                )
            ],
            restartCount: restartCount
        )
        store.add(job)
        return job
    }

    // MARK: - Enqueue

    @Test func enqueueCreatesAJobAndStartsEveryFileAtOnce() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }

        let jobId = await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10), file("red.sav", 20)])

        #expect(jobId != nil)
        let job = try #require(fixture.store.job(romId: 7))
        #expect(job.state == .running)
        // Both transfers are in flight before either has reported anything, the
        // second file does not wait for the first.
        #expect(job.files.map(\.state) == [.running, .running])
        #expect(fixture.client.startedKeys.map(\.fileName) == ["red.gb", "red.sav"])
        #expect(fixture.client.startedPaths == ["/api/roms/7/content/red.gb", "/api/roms/7/content/red.sav"])
        #expect(fixture.coordinator.jobs.count == 1)
        #expect(fixture.coordinator.activeCount == 1)
        #expect(fixture.coordinator.state(forRomId: 7) == .running)
        #expect(FileManager.default.fileExists(atPath: fixture.romDirectory.path))
    }

    @Test func enqueueingTheSameRomTwiceKeepsOneJob() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let files = [file("red.gb", 10)]

        let first = await fixture.coordinator.enqueue(rom: rom(), files: files)
        let second = await fixture.coordinator.enqueue(rom: rom(), files: files)

        #expect(first != nil)
        #expect(second == nil)
        #expect(fixture.store.allJobs().count == 1)
        #expect(fixture.coordinator.jobs.count == 1)
        #expect(fixture.client.startedTransfers.count == 1)
    }

    // MARK: - Progress

    @Test func progressAddsUpTheBytesOfEveryFile() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(
            rom: rom(),
            files: [file("red.gb", 10), file("red.sav", 20)]
        ))

        fixture.coordinator.downloadProgressed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            totalBytesWritten: 5,
            bytesPerSecond: 100
        )
        fixture.coordinator.downloadProgressed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.sav"),
            totalBytesWritten: 5,
            bytesPerSecond: 50
        )

        let entry = try #require(fixture.coordinator.entry(forRomId: 7))
        #expect(entry.progress == 10.0 / 30.0)
        // Parallel transfers of one ROM are shown as one rate.
        #expect(entry.bytesPerSecond == 150)
    }

    @Test func progressNeverRunsPastAFullBar() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))

        fixture.coordinator.downloadProgressed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            totalBytesWritten: 40,
            bytesPerSecond: nil
        )

        #expect(fixture.coordinator.progress(forRomId: 7) == 1)
    }

    @Test func oneFileWithoutAnAnnouncedSizeMakesTheProgressUnknown() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(
            rom: rom(),
            files: [file("red.gb", 10), file("disc.bin", 0)]
        ))

        fixture.coordinator.downloadProgressed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            totalBytesWritten: 5,
            bytesPerSecond: nil
        )

        // Nil rather than a guess: a total built from a size that is not known
        // yet would move as soon as it is.
        #expect(fixture.coordinator.progress(forRomId: 7) == nil)
    }

    // MARK: - Completion

    @Test func finishingEveryFileWritesTheMetadataAndClearsTheJob() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(
            rom: rom(),
            files: [file("red.gb", 10), file("red.sav", 20)]
        ))
        write("red.gb", bytes: 10, in: fixture.romDirectory)
        write("red.sav", bytes: 22, in: fixture.romDirectory)

        fixture.coordinator.downloadFinished(key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"), bytesOnDisk: 10)
        // One file of two is not a finished job.
        #expect(fixture.store.job(id: jobId) != nil)
        #expect(fixture.repository.saved.isEmpty)

        fixture.coordinator.downloadFinished(key: DownloadTaskKey(jobId: jobId, fileName: "red.sav"), bytesOnDisk: 22)

        #expect(fixture.store.job(id: jobId) == nil)
        #expect(fixture.coordinator.jobs.isEmpty)
        #expect(fixture.coordinator.activeCount == 0)
        let stored = try #require(fixture.repository.saved.first)
        #expect(stored.id == 7)
        #expect(stored.platformName == "gb")
        #expect(stored.localDirectory == "gb/Pokemon Red")
        #expect(stored.files.map(\.fileName) == ["red.gb", "red.sav"])
        // The sizes come off the disk, not from the announced metadata.
        #expect(stored.totalSizeBytes == 32)
    }

    /// The case `DownloadQueueManager` had to guard by hand: a checkpoint that
    /// arrives after the download is over must not put it back on the queue.
    @Test func aLateProgressReportDoesNotReviveAFinishedJob() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))
        write("red.gb", bytes: 10, in: fixture.romDirectory)
        fixture.coordinator.downloadFinished(key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"), bytesOnDisk: 10)
        #expect(fixture.store.job(id: jobId) == nil)

        fixture.coordinator.downloadProgressed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            totalBytesWritten: 4,
            bytesPerSecond: 10
        )

        #expect(fixture.store.allJobs().isEmpty)
        #expect(fixture.coordinator.jobs.isEmpty)
        #expect(fixture.coordinator.state(forRomId: 7) == nil)
    }

    // MARK: - Cancellation

    @Test func cancelStopsTheTransfersCleansUpAndForgetsTheJob() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(
            rom: rom(),
            files: [file("red.gb", 10), file("red.sav", 20)]
        ))
        write("red.gb", bytes: 4, in: fixture.romDirectory)

        fixture.coordinator.cancel(romId: 7)

        #expect(fixture.client.cancelledJobIds == [jobId])
        #expect(fixture.store.job(id: jobId) == nil)
        #expect(fixture.coordinator.jobs.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.romDirectory.appendingPathComponent("red.gb").path))

        // The cancels the session reports back must not turn into an error, and
        // must not put the job back on the queue.
        fixture.coordinator.downloadFailed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            error: URLError(.cancelled),
            isCancellation: true
        )
        fixture.coordinator.downloadFailed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.sav"),
            error: URLError(.cancelled),
            isCancellation: true
        )

        #expect(fixture.store.allJobs().isEmpty)
        #expect(fixture.coordinator.jobs.isEmpty)
    }

    @Test func aFinishedFileArrivingAfterACancelIsIgnored() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))

        fixture.coordinator.cancel(jobId: jobId)
        fixture.coordinator.downloadFinished(key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"), bytesOnDisk: 10)

        #expect(fixture.store.allJobs().isEmpty)
        #expect(fixture.repository.saved.isEmpty)
    }

    // MARK: - Legacy content path

    @Test func aRejectedPerFilePathIsRetriedOnTheLegacyPath() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))

        fixture.coordinator.downloadRejected(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            statusCode: 404,
            serverMessage: nil
        )

        #expect(fixture.client.startCount(forFileNamed: "red.gb") == 2)
        #expect(fixture.client.startedPaths == ["/api/roms/7/content/red.gb", "/api/roms/7/content"])
        let job = try #require(fixture.store.job(id: jobId))
        #expect(job.state == .running)
        #expect(job.files[0].usesLegacyContentPath)
        #expect(job.files[0].state == .running)
        #expect(job.errorMessage == nil)
    }

    @Test func aRejectedLegacyPathFailsTheJobWithAReason() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))
        let key = DownloadTaskKey(jobId: jobId, fileName: "red.gb")

        fixture.coordinator.downloadRejected(key: key, statusCode: 404, serverMessage: nil)
        fixture.coordinator.downloadRejected(key: key, statusCode: 404, serverMessage: "Not found")

        // No third attempt: both paths have answered.
        #expect(fixture.client.startCount(forFileNamed: "red.gb") == 2)
        let job = try #require(fixture.store.job(id: jobId))
        #expect(job.state == .failed)
        #expect(job.files[0].state == .failed)
        #expect(job.errorMessage?.contains("404") == true)
        #expect(fixture.coordinator.errorMessage(forRomId: 7)?.isEmpty == false)
        #expect(fixture.coordinator.activeCount == 0)
        #expect(fixture.client.cancelledJobIds == [jobId])
    }

    @Test func retryingAFailedJobStartsItsOutstandingFilesAgain() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))
        fixture.coordinator.downloadRejected(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            statusCode: 500,
            serverMessage: nil
        )
        #expect(fixture.store.job(id: jobId)?.state == .failed)
        fixture.client.reset()

        await fixture.coordinator.retry(romId: 7)

        #expect(fixture.client.startCount(forFileNamed: "red.gb") == 1)
        let job = try #require(fixture.store.job(id: jobId))
        #expect(job.state == .running)
        #expect(job.errorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.romDirectory.path))
    }

    /// A job can fail with every file already on disk, for instance when
    /// finishing it throws. There is nothing left to transfer then, and the
    /// retry has to finish it rather than park it as running.
    @Test func retryingAJobThatFailedWhileBeingFinishedFinishesIt() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))

        // Reported as arrived while it is not on disk, which is what makes
        // finishing throw.
        fixture.coordinator.downloadFinished(key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"), bytesOnDisk: 10)
        let failed = try #require(fixture.store.job(id: jobId))
        #expect(failed.state == .failed)
        #expect(failed.files.map(\.state) == [.downloaded])
        fixture.client.reset()
        write("red.gb", bytes: 10, in: fixture.romDirectory)

        await fixture.coordinator.retry(romId: 7)

        #expect(fixture.client.startedTransfers.isEmpty)
        #expect(fixture.store.job(id: jobId) == nil)
        #expect(fixture.repository.saved.map(\.id) == [7])
        #expect(fixture.coordinator.jobs.isEmpty)
    }

    // MARK: - Resumption

    @Test func resumptionRestartsAFileTheSystemNoLongerTransfers() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let job = seedJob(in: fixture.store)
        fixture.client.liveKeys = []

        await fixture.coordinator.resumeInterruptedJobs()

        #expect(fixture.client.startedKeys == [DownloadTaskKey(jobId: job.id, fileName: "red.gb")])
        let resumed = try #require(fixture.store.job(id: job.id))
        #expect(resumed.state == .running)
        #expect(resumed.restartCount == 1)
        #expect(fixture.coordinator.jobs.count == 1)
    }

    @Test func resumptionLeavesAFileAloneWhileItsTransferIsStillLive() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let job = seedJob(in: fixture.store)
        fixture.client.liveKeys = [DownloadTaskKey(jobId: job.id, fileName: "red.gb")]

        await fixture.coordinator.resumeInterruptedJobs()

        #expect(fixture.client.startedTransfers.isEmpty)
        // Untouched down to the bytes it had got to, a live transfer keeps
        // reporting against them.
        #expect(fixture.store.job(id: job.id) == job)
    }

    @Test func resumptionGivesUpAfterThreeRestarts() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let job = seedJob(in: fixture.store)
        fixture.client.liveKeys = []

        for _ in 0..<4 {
            await fixture.coordinator.resumeInterruptedJobs()
        }

        #expect(fixture.client.startCount(forFileNamed: "red.gb") == DownloadJobCoordinator.maximumAutomaticRestarts)
        let failed = try #require(fixture.store.job(id: job.id))
        #expect(failed.state == .failed)
        #expect(failed.restartCount == DownloadJobCoordinator.maximumAutomaticRestarts)
        #expect(failed.errorMessage?.isEmpty == false)
    }

    @Test func resumptionFinishesAJobWhoseFilesAreAllOnDisk() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let job = seedJob(in: fixture.store, fileState: .downloaded)
        write("red.gb", bytes: 10, in: fixture.romDirectory)
        fixture.client.liveKeys = []

        await fixture.coordinator.resumeInterruptedJobs()

        #expect(fixture.client.startedTransfers.isEmpty)
        #expect(fixture.store.job(id: job.id) == nil)
        #expect(fixture.repository.saved.map(\.id) == [7])
        #expect(fixture.coordinator.jobs.isEmpty)
    }

    @Test func resumptionOnAnEmptyQueueDoesNothing() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }

        await fixture.coordinator.resumeInterruptedJobs()

        #expect(fixture.coordinator.jobs.isEmpty)
        #expect(fixture.client.startedTransfers.isEmpty)
    }

    // MARK: - Storage

    @Test func theStorageCheckCountsTheOpenBytesOfAnotherJob() async throws {
        let fixture = makeFixture(availableBytes: 100)
        defer { fixture.remove() }

        _ = await fixture.coordinator.enqueue(rom: rom(id: 7), files: [file("red.gb", 60)])
        #expect(fixture.probe.requestedBytes == 60)

        let secondId = await fixture.coordinator.enqueue(rom: rom(id: 8, name: "Pokemon Blue"), files: [file("blue.gb", 60)])

        // Two ROMs at once have to fit together, not one at a time.
        #expect(fixture.probe.requestedBytes == 120)
        let second = try #require(fixture.store.job(romId: 8))
        #expect(second.id == secondId)
        #expect(second.state == .failed)
        #expect(second.errorMessage?.contains("Insufficient storage") == true)
        #expect(fixture.client.startCount(forFileNamed: "blue.gb") == 0)
        // The ROM that was already running is untouched by the refusal.
        #expect(fixture.store.job(romId: 7)?.state == .running)
    }

    // MARK: - Destinations

    @Test func theDestinationOfATransferPointsIntoTheRomDirectory() async throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let jobId = try #require(await fixture.coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))
        let key = DownloadTaskKey(jobId: jobId, fileName: "red.gb")

        #expect(fixture.coordinator.destinationURL(for: key)?.path
            == fixture.romsBaseURL.appendingPathComponent("gb/Pokemon Red/red.gb").path)

        fixture.coordinator.cancel(jobId: jobId)

        // A file arriving for a job that is gone has nowhere to go.
        #expect(fixture.coordinator.destinationURL(for: key) == nil)
    }

    /// A job of an earlier app session has no prepared destination in this one,
    /// so its directory is put together again from the path it carries and the
    /// library root, which is the same root the finalizer files it under.
    @Test func aJobFromAnEarlierSessionResolvesItsDestinationFromTheLibraryRoot() throws {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let job = seedJob(in: fixture.store)

        let resolved = fixture.coordinator.destinationURL(
            for: DownloadTaskKey(jobId: job.id, fileName: "red.gb")
        )

        #expect(resolved?.path == fixture.romDirectory.appendingPathComponent("red.gb").path)
        // A file the job does not own is not this job's business.
        #expect(fixture.coordinator.destinationURL(for: DownloadTaskKey(jobId: job.id, fileName: "blue.gb")) == nil)
    }

    /// The finding this guards: the destination of a transfer used to be built
    /// from a ROM library root of this type's own while the finalizer built its
    /// directory from its repository, so the two could point apart. Wired to two
    /// different libraries on purpose, the transfer still has to land in the
    /// directory the finalizer prepared and later validates.
    @Test func aTransferLandsInTheDirectoryTheFinalizerPrepared() async throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let preparedDirectory = root.appendingPathComponent("Prepared/Somewhere Else", isDirectory: true)
        let finalizer = RelocatingFinalizer(
            relativePath: "Prepared/Somewhere Else",
            directoryURL: preparedDirectory
        )
        let store = DownloadJobStore(rootDirectory: root.appendingPathComponent("queue", isDirectory: true))
        let coordinator = DownloadJobCoordinator(
            transferClient: FakeBackgroundTransferClient(),
            store: store,
            finalizer: finalizer,
            apiClient: StubDownloadRequestClient(),
            romRepository: CoordinatorROMs(romsBaseURL: root.appendingPathComponent("Never read", isDirectory: true))
        )

        let jobId = try #require(await coordinator.enqueue(rom: rom(), files: [file("red.gb", 10)]))
        let key = DownloadTaskKey(jobId: jobId, fileName: "red.gb")
        let resolved = try #require(coordinator.destinationURL(for: key))

        #expect(resolved.path == preparedDirectory.appendingPathComponent("red.gb").path)
        // The path the job carries follows the finalizer too, so the next app
        // session rebuilds that same directory instead of the one this type
        // worked out when the job was queued.
        #expect(store.job(id: jobId)?.romDirectoryPath == "Prepared/Somewhere Else")

        coordinator.downloadFinished(key: key, bytesOnDisk: 10)

        // The directory the delegate was told to write into is the directory
        // the finalizer was handed afterwards. That is the divergence: as long
        // as both come off the same destination, they cannot disagree.
        #expect(finalizer.finishedDestinations.map(\.directoryURL.path) == [resolved.deletingLastPathComponent().path])
        #expect(store.job(id: jobId) == nil)
    }

    // MARK: - Queue file compatibility

    @Test func aQueueFileWrittenWithoutTheErrorFieldStillDecodes() throws {
        let root = makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let queueDirectory = root.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        let json = """
        [
          {
            "id": "0FCB79D0-8D3E-4C33-9B4C-0B1E1D2C3A44",
            "romId": 7,
            "rom": { "id": 7, "name": "Pokemon Red", "platformId": 3, "platformSlug": "gb" },
            "platformName": "gb",
            "romDirectoryPath": "gb/Pokemon Red",
            "createdAt": 0,
            "state": "running",
            "restartCount": 1,
            "files": [
              {
                "fileName": "red.gb",
                "expectedSizeBytes": 10,
                "usesLegacyContentPath": false,
                "state": "running",
                "receivedBytes": 4
              }
            ]
          }
        ]
        """
        try Data(json.utf8).write(to: queueDirectory.appendingPathComponent(DownloadJobStore.queueFileName))

        let store = DownloadJobStore(rootDirectory: queueDirectory)
        let jobs = store.allJobs()

        #expect(jobs.count == 1)
        let job = try #require(jobs.first)
        #expect(job.romId == 7)
        #expect(job.restartCount == 1)
        #expect(job.errorMessage == nil)
        #expect(job.files.map(\.receivedBytes) == [4])

        // And it stays readable once the field is written back.
        var failed = job
        failed.state = .failed
        failed.errorMessage = "Server rejected the download"
        store.replace(failed)
        #expect(DownloadJobStore(rootDirectory: queueDirectory).allJobs().first?.errorMessage == "Server rejected the download")
    }
}
