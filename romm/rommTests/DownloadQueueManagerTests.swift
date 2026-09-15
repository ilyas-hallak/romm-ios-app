import Testing
import Foundation
@testable import romm

/// The download queue with no file system behind it: every job lives in memory.
private final class QueueJobStore: PDownloadJobStore, @unchecked Sendable {
    private var jobs: [DownloadJob] = []

    func allJobs() -> [DownloadJob] { jobs }
    func job(id: UUID) -> DownloadJob? { jobs.first { $0.id == id } }
    func job(romId: Int) -> DownloadJob? { jobs.first { $0.romId == romId } }

    func add(_ job: DownloadJob) {
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
    }

    func replace(_ job: DownloadJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
    }

    func updateFile(jobId: UUID, fileName: String, _ mutate: (inout DownloadJobFile) -> Void) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobId }),
              let fileIndex = jobs[jobIndex].files.firstIndex(where: { $0.fileName == fileName }) else { return }
        mutate(&jobs[jobIndex].files[fileIndex])
    }

    func remove(jobId: UUID) {
        jobs.removeAll { $0.id == jobId }
    }
}

/// Prepares and finishes downloads without touching disk, and records what it
/// was asked to give back.
private final class QueueFinalizer: PROMDownloadFinalizer, @unchecked Sendable {
    var prepareError: Error?
    private(set) var finishedRomIds: [Int] = []
    private(set) var cleanedUpPaths: [String] = []

    func prepare(rom: Rom, files: [RomFileInfo], reservedBytes: Int64) async throws -> ROMDownloadDestination {
        if let prepareError { throw prepareError }
        return ROMDownloadDestination(
            relativePath: "gb/\(rom.name)",
            directoryURL: URL(fileURLWithPath: "/tmp/queue-tests/gb/\(rom.name)"),
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
        finishedRomIds.append(rom.id)
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

    func cleanUp(_ destination: ROMDownloadDestination) {
        cleanedUpPaths.append(destination.relativePath)
    }
}

/// The ROM library root the coordinator falls back to for jobs it did not
/// prepare itself. Nothing in these tests touches the disk under it.
private final class QueueROMs: PLocalROMRepository, @unchecked Sendable {
    let romsBaseURL = URL(fileURLWithPath: "/tmp/queue-tests/ROMs")

    func getAllDownloadedROMs() throws -> [DownloadedROM] { [] }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { nil }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { 0 }
}

/// Says which files a ROM is made of, or refuses to.
private final class QueueFileList: PROMFileListProvider, @unchecked Sendable {
    var files: [RomFileInfo]
    var error: Error?
    private(set) var askedForRomIds: [Int] = []

    init(files: [RomFileInfo]) {
        self.files = files
    }

    func files(for rom: Rom) async throws -> [RomFileInfo] {
        askedForRomIds.append(rom.id)
        if let error { throw error }
        return files
    }
}

/// Hands out a request for any download path, so nothing reaches the network.
private final class QueueRequestAPIClient: StubRommAPIClient {
    override func makeDownloadRequest(path: String) throws -> URLRequest {
        URLRequest(url: URL(string: "https://romm.invalid/\(path)")!)
    }
}

/// Writes down what the queue asks of the live activity.
///
/// `canShowActivities` set to false is the simulator and everything before
/// iOS 26: the real controller's scheduler refuses the request there and every
/// call ends up doing nothing, which the queue has to survive unchanged.
@MainActor
private final class FakeContinuedTaskController: PDownloadContinuedTaskController {

    struct Started: Equatable {
        let jobId: UUID
        let title: String
        let subtitle: String
        let totalBytes: Int64?
    }

    struct Updated: Equatable {
        let jobId: UUID
        let completedBytes: Int64
        let totalBytes: Int64?
        let subtitle: String?
    }

    struct Finished: Equatable {
        let jobId: UUID
        let success: Bool
    }

    var canShowActivities = true

    private(set) var starts: [Started] = []
    private(set) var updates: [Updated] = []
    private(set) var finishes: [Finished] = []

    func start(jobId: UUID, title: String, subtitle: String, totalBytes: Int64?) {
        guard canShowActivities else { return }
        starts.append(Started(jobId: jobId, title: title, subtitle: subtitle, totalBytes: totalBytes))
    }

    func update(jobId: UUID, completedBytes: Int64, totalBytes: Int64?, subtitle: String?) {
        guard canShowActivities else { return }
        updates.append(Updated(
            jobId: jobId,
            completedBytes: completedBytes,
            totalBytes: totalBytes,
            subtitle: subtitle
        ))
    }

    func finish(jobId: UUID, success: Bool) {
        guard canShowActivities else { return }
        finishes.append(Finished(jobId: jobId, success: success))
    }
}

private struct QueueFileListError: LocalizedError {
    var errorDescription: String? { "ROM details could not be read" }
}

private struct QueueTransferError: LocalizedError {
    var errorDescription: String? { "The transfer stopped" }
}

@MainActor
struct DownloadQueueManagerTests {

    // MARK: - Fixture

    private struct Fixture {
        let store: QueueJobStore
        let client: FakeBackgroundTransferClient
        let finalizer: QueueFinalizer
        let fileList: QueueFileList
        let activities: FakeContinuedTaskController
        let coordinator: DownloadJobCoordinator
        let manager: DownloadQueueManager
    }

    private func makeFixture(
        store: QueueJobStore = QueueJobStore(),
        files: [RomFileInfo]? = nil
    ) -> Fixture {
        let client = FakeBackgroundTransferClient()
        let finalizer = QueueFinalizer()
        let fileList = QueueFileList(files: files ?? [file("red.gb", 10), file("red.sav", 30)])
        let activities = FakeContinuedTaskController()
        let coordinator = DownloadJobCoordinator(
            transferClient: client,
            store: store,
            finalizer: finalizer,
            apiClient: QueueRequestAPIClient(),
            romRepository: QueueROMs()
        )
        let manager = DownloadQueueManager(
            transferClient: client,
            coordinator: coordinator,
            fileListProvider: fileList,
            continuedTaskController: activities
        )
        return Fixture(
            store: store,
            client: client,
            finalizer: finalizer,
            fileList: fileList,
            activities: activities,
            coordinator: coordinator,
            manager: manager
        )
    }

    private func rom(id: Int = 7, name: String = "Pokemon Red", sizeBytes: Int? = nil) -> Rom {
        Rom(id: id, name: name, platformId: 3, urlCover: nil, sizeBytes: sizeBytes, platformSlug: "gb")
    }

    private func file(_ name: String, _ size: Int64) -> RomFileInfo {
        RomFileInfo(
            id: name,
            fileName: name,
            fileSizeBytes: size,
            fileExtension: (name as NSString).pathExtension
        )
    }

    private func job(
        romId: Int = 7,
        name: String = "Pokemon Red",
        state: DownloadJobState,
        expectedSizeBytes: Int64 = 100,
        receivedBytes: Int64 = 0,
        errorMessage: String? = nil
    ) -> DownloadJob {
        DownloadJob(
            romId: romId,
            rom: DownloadJobRomSnapshot(id: romId, name: name, platformId: 3, platformSlug: "gb"),
            platformName: "Game Boy",
            romDirectoryPath: "Game Boy/\(name)",
            state: state,
            files: [
                DownloadJobFile(
                    fileName: "red.gb",
                    expectedSizeBytes: expectedSizeBytes,
                    state: state == .failed ? .failed : .running,
                    receivedBytes: receivedBytes
                )
            ],
            errorMessage: errorMessage
        )
    }

    /// Lets the queue's own tasks and its reconciliation run until the queue
    /// says what the test is waiting for. Everything in here is main actor bound
    /// and waits on nothing real, so yielding is enough and no test has to sleep.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }

    /// Same, for the tests that expect nothing more to happen and so have no
    /// condition to wait for.
    private func settle() async {
        for _ in 0..<200 {
            await Task.yield()
        }
    }

    /// The queue has taken the ROM on and its transfers are under way.
    private func isRunning(_ romId: Int, in store: QueueJobStore) -> Bool {
        store.job(romId: romId)?.state == .running
    }

    // MARK: - Status mapping

    @Test func everyJobStateBecomesATaskStatus() async throws {
        let store = QueueJobStore()
        store.add(job(romId: 1, name: "Queued", state: .queued))
        store.add(job(romId: 2, name: "Running", state: .running))
        store.add(job(romId: 3, name: "Finalizing", state: .finalizing))
        store.add(job(romId: 4, name: "Cancelling", state: .cancelling))
        store.add(job(romId: 5, name: "Failed", state: .failed, errorMessage: "Disk full"))
        let fixture = makeFixture(store: store)

        #expect(fixture.manager.status(forRomId: 1) == .queued)
        #expect(fixture.manager.status(forRomId: 2) == .downloading(progress: 0, bytesPerSecond: nil))
        #expect(fixture.manager.status(forRomId: 3) == .finalizing)
        #expect(fixture.manager.status(forRomId: 4) == .cancelled)
        #expect(fixture.manager.status(forRomId: 5) == .failed("Disk full"))
        // Only the ones that are still on their way count as active, and none of
        // them is finished, so the Downloads tab is not asked to reload.
        #expect(fixture.manager.activeCount == 3)
        #expect(fixture.manager.finishedCount == 0)
    }

    @Test func runningJobCarriesProgressAndRate() async throws {
        let store = QueueJobStore()
        let seeded = job(state: .running, expectedSizeBytes: 100)
        store.add(seeded)
        let fixture = makeFixture(store: store)

        fixture.coordinator.downloadProgressed(
            key: DownloadTaskKey(jobId: seeded.id, fileName: "red.gb"),
            totalBytesWritten: 25,
            bytesPerSecond: 2_048
        )

        #expect(fixture.manager.status(forRomId: 7) == .downloading(progress: 0.25, bytesPerSecond: 2_048))
    }

    @Test func failedJobWithoutAMessageStillReadsAsFailed() async throws {
        let store = QueueJobStore()
        store.add(job(state: .failed))
        let fixture = makeFixture(store: store)

        #expect(fixture.manager.status(forRomId: 7) == .failed("Download failed"))
        #expect(fixture.manager.tasks.first?.isActive == false)
    }

    // MARK: - Enqueue

    @Test func enqueueQueuesTheRomAndStartsEveryFile() async throws {
        let fixture = makeFixture()

        fixture.manager.enqueue(rom: rom())

        // The row is there before the file list has even been asked for, so the
        // Download button does not spring back.
        #expect(fixture.manager.tasks.map(\.id) == [7])
        #expect(fixture.manager.status(forRomId: 7) == .queued)

        await settle { isRunning(7, in: fixture.store) }
        #expect(fixture.client.startedKeys.map(\.fileName) == ["red.gb", "red.sav"])
        #expect(fixture.manager.tasks.count == 1)
        #expect(fixture.manager.status(forRomId: 7) == .downloading(progress: 0, bytesPerSecond: nil))
        #expect(fixture.manager.activeCount == 1)
    }

    @Test func enqueueingARomThatIsAlreadyQueuedDoesNothing() async throws {
        let fixture = makeFixture()

        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        fixture.manager.enqueue(rom: rom())
        await settle()

        #expect(fixture.fileList.askedForRomIds == [7])
        #expect(fixture.store.allJobs().count == 1)
        #expect(fixture.manager.tasks.count == 1)
    }

    @Test func enqueueingTwiceBeforeTheFileListArrivesDoesNothingEither() async throws {
        let fixture = makeFixture()

        fixture.manager.enqueue(rom: rom())
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }

        #expect(fixture.fileList.askedForRomIds == [7])
        #expect(fixture.manager.tasks.count == 1)
    }

    @Test func aRomWhoseFileListCannotBeReadFails() async throws {
        let fixture = makeFixture()
        fixture.fileList.error = QueueFileListError()

        fixture.manager.enqueue(rom: rom())
        await settle { fixture.manager.status(forRomId: 7) != .queued }

        // The download never became a job, but the user still has to see that it
        // did not happen, and be able to ask for it again.
        #expect(fixture.manager.status(forRomId: 7) == .failed("ROM details could not be read"))
        #expect(fixture.store.allJobs().isEmpty)

        fixture.fileList.error = nil
        fixture.manager.retry(id: 7)
        await settle { isRunning(7, in: fixture.store) }

        #expect(fixture.manager.status(forRomId: 7) == .downloading(progress: 0, bytesPerSecond: nil))
        #expect(fixture.manager.tasks.count == 1)
    }

    // MARK: - Cancel

    @Test func cancelStopsTheTransfersAndMarksTheRow() async throws {
        let fixture = makeFixture()
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        let jobId = try #require(fixture.store.job(romId: 7)).id

        fixture.manager.cancel(id: 7)

        #expect(fixture.client.cancelledJobIds == [jobId])
        #expect(fixture.store.allJobs().isEmpty)
        #expect(fixture.finalizer.cleanedUpPaths == ["gb/Pokemon Red"])
        // The row stays as a settled one, so cancelling is visible feedback
        // rather than a row that just disappears.
        #expect(fixture.manager.status(forRomId: 7) == .cancelled)
        #expect(fixture.manager.activeCount == 0)
        #expect(fixture.manager.finishedCount == 0)
    }

    @Test func cancelBeforeTheFileListArrivesLeavesNothingBehind() async throws {
        let fixture = makeFixture()

        fixture.manager.enqueue(rom: rom())
        fixture.manager.cancel(id: 7)
        await settle()

        #expect(fixture.manager.tasks.isEmpty)
        #expect(fixture.store.allJobs().isEmpty)
        #expect(fixture.client.startedTransfers.isEmpty)
    }

    @Test func aCancelledRomCanBeQueuedAgain() async throws {
        let fixture = makeFixture()
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        fixture.manager.cancel(id: 7)

        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }

        #expect(fixture.manager.tasks.count == 1)
        #expect(fixture.manager.status(forRomId: 7) == .downloading(progress: 0, bytesPerSecond: nil))
    }

    // MARK: - Completion

    @Test func aJobTheCoordinatorLetsGoOfBecomesAFinishedRow() async throws {
        let fixture = makeFixture(files: [file("red.gb", 10)])
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        let jobId = try #require(fixture.store.job(romId: 7)).id

        fixture.coordinator.downloadFinished(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            bytesOnDisk: 10
        )

        // The coordinator drops a stored job, and the queue screen keeps showing
        // it under "Completed" until it is cleared.
        #expect(fixture.finalizer.finishedRomIds == [7])
        #expect(fixture.store.allJobs().isEmpty)
        await settle { fixture.manager.finishedCount == 1 }
        #expect(fixture.manager.status(forRomId: 7) == .finished)
        #expect(fixture.manager.activeCount == 0)
        #expect(fixture.manager.tasks.count == 1)
    }

    // MARK: - Removing and clearing

    @Test func removeLeavesARunningDownloadAlone() async throws {
        let fixture = makeFixture()
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }

        fixture.manager.remove(id: 7)

        #expect(fixture.manager.tasks.count == 1)
        #expect(fixture.store.allJobs().count == 1)
        #expect(fixture.client.cancelledJobIds.isEmpty)
    }

    @Test func removeTakesAFailedJobOutWithoutLeavingARow() async throws {
        let store = QueueJobStore()
        store.add(job(state: .failed, errorMessage: "Disk full"))
        let fixture = makeFixture(store: store)

        fixture.manager.remove(id: 7)

        #expect(fixture.manager.tasks.isEmpty)
        #expect(fixture.store.allJobs().isEmpty)
    }

    @Test func clearCompletedKeepsWhatIsStillRunning() async throws {
        let store = QueueJobStore()
        store.add(job(romId: 9, name: "Blue", state: .failed, errorMessage: "Disk full"))
        let fixture = makeFixture(store: store)
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        fixture.manager.enqueue(rom: rom(id: 8, name: "Yellow"))
        await settle { isRunning(8, in: fixture.store) }
        fixture.manager.cancel(id: 8)

        #expect(fixture.manager.tasks.count == 3)

        fixture.manager.clearCompleted()

        // The cancelled row and the failed job go, the running download stays.
        #expect(fixture.manager.tasks.map(\.id) == [7])
        #expect(fixture.manager.status(forRomId: 7) == .downloading(progress: 0, bytesPerSecond: nil))
        #expect(fixture.store.allJobs().map(\.romId) == [7])
    }

    // MARK: - App lifecycle

    @Test func backgroundSessionEventsAreHandedToTheSession() async throws {
        let fixture = makeFixture()
        var handlerCalls = 0

        fixture.manager.handleBackgroundSessionEvents { handlerCalls += 1 }
        fixture.client.launchCompletionHandler?()

        #expect(handlerCalls == 1)
    }

    @Test func onlyTheAppsOwnSessionIdentifierIsClaimed() async throws {
        let fixture = makeFixture()

        // Asked of the session the queue actually holds, not of the app wide
        // identifier, so an injected session answers for itself.
        #expect(fixture.manager.handlesBackgroundSession(identifier: fixture.client.identifier))
        #expect(!fixture.manager.handlesBackgroundSession(
            identifier: BackgroundDownloadSession.defaultIdentifier
        ))
        #expect(!fixture.manager.handlesBackgroundSession(identifier: "com.example.other-session"))
    }

    @Test func resumingPutsAnInterruptedJobBackOnItsFeet() async throws {
        let store = QueueJobStore()
        store.add(job(state: .running, receivedBytes: 40))
        let fixture = makeFixture(store: store)

        await fixture.manager.resumeInterruptedJobs()

        #expect(fixture.client.startedKeys.map(\.fileName) == ["red.gb"])
        #expect(fixture.manager.activeCount == 1)
        // The bytes the interrupted transfer had already reported are kept, so
        // the bar carries on where it stopped instead of jumping back to zero.
        #expect(fixture.manager.status(forRomId: 7) == .downloading(progress: 0.4, bytesPerSecond: nil))
    }

    // MARK: - Live activity

    @Test func enqueueAsksForOneActivityNamedAfterTheRom() async throws {
        let fixture = makeFixture()

        fixture.manager.enqueue(rom: rom(sizeBytes: 40))

        // Asked for while the tap is still on the stack, long before the file
        // list is back: the scheduler grants nothing that comes later.
        let started = try #require(fixture.activities.starts.first)
        #expect(fixture.activities.starts.count == 1)
        #expect(started.title == "Pokemon Red")
        #expect(started.subtitle == "Preparing")
        #expect(started.totalBytes == 40)

        await settle { isRunning(7, in: fixture.store) }
        #expect(fixture.activities.starts.count == 1)
        #expect(fixture.activities.finishes.isEmpty)
    }

    @Test func aRomOfUnknownSizeStartsItsActivityWithoutATotal() async throws {
        let fixture = makeFixture()

        fixture.manager.enqueue(rom: rom())

        #expect(fixture.activities.starts.count == 1)
        #expect(fixture.activities.starts.first?.totalBytes == nil)
    }

    @Test func enqueueingTheSameRomAgainLeavesItWithOneActivity() async throws {
        let fixture = makeFixture()

        fixture.manager.enqueue(rom: rom())
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        fixture.manager.enqueue(rom: rom())
        await settle()

        #expect(fixture.activities.starts.count == 1)
        #expect(fixture.activities.finishes.isEmpty)
    }

    @Test func progressReachesTheActivityAsBytesAndAsARate() async throws {
        let fixture = makeFixture()
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        let jobId = try #require(fixture.store.job(romId: 7)).id
        let activityId = try #require(fixture.activities.starts.first).jobId

        fixture.coordinator.downloadProgressed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            totalBytesWritten: 6,
            bytesPerSecond: 2_048
        )
        await settle { fixture.activities.updates.last?.completedBytes == 6 }

        // The bytes of every file of the job added up against their announced
        // sizes, and the rate in the words the queue screen uses for it.
        #expect(fixture.activities.updates.last == FakeContinuedTaskController.Updated(
            jobId: activityId,
            completedBytes: 6,
            totalBytes: 40,
            subtitle: DownloadTask.formattedRate(2_048)
        ))
    }

    @Test func aStoredDownloadEndsItsActivityAsASuccess() async throws {
        let fixture = makeFixture(files: [file("red.gb", 10)])
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        let jobId = try #require(fixture.store.job(romId: 7)).id
        let activityId = try #require(fixture.activities.starts.first).jobId

        fixture.coordinator.downloadFinished(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            bytesOnDisk: 10
        )
        await settle { fixture.manager.finishedCount == 1 }

        #expect(fixture.activities.finishes == [.init(jobId: activityId, success: true)])
    }

    @Test func cancellingEndsItsActivityAsAFailure() async throws {
        let fixture = makeFixture()
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        let activityId = try #require(fixture.activities.starts.first).jobId

        fixture.manager.cancel(id: 7)
        await settle()

        #expect(fixture.activities.finishes == [.init(jobId: activityId, success: false)])
    }

    @Test func cancellingBeforeTheFileListArrivesStillEndsTheActivity() async throws {
        let fixture = makeFixture()
        fixture.manager.enqueue(rom: rom())
        let activityId = try #require(fixture.activities.starts.first).jobId

        fixture.manager.cancel(id: 7)
        await settle()

        // No job ever existed here, so nothing downstream could have ended it.
        #expect(fixture.activities.finishes == [.init(jobId: activityId, success: false)])
    }

    @Test func aFailedTransferEndsItsActivityAsAFailure() async throws {
        let fixture = makeFixture(files: [file("red.gb", 10)])
        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        let jobId = try #require(fixture.store.job(romId: 7)).id
        let activityId = try #require(fixture.activities.starts.first).jobId

        fixture.coordinator.downloadFailed(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            error: QueueTransferError(),
            isCancellation: false
        )
        await settle { !fixture.activities.finishes.isEmpty }

        // A failed job stays in the queue, so the activity has to end on the
        // state rather than on the job going away.
        #expect(fixture.manager.status(forRomId: 7) == .failed("The transfer stopped"))
        #expect(fixture.activities.finishes == [.init(jobId: activityId, success: false)])
    }

    @Test func aRomWhoseFileListCannotBeReadEndsItsActivity() async throws {
        let fixture = makeFixture()
        fixture.fileList.error = QueueFileListError()

        fixture.manager.enqueue(rom: rom())
        let activityId = try #require(fixture.activities.starts.first).jobId
        await settle { !fixture.activities.finishes.isEmpty }

        #expect(fixture.activities.finishes == [.init(jobId: activityId, success: false)])
    }

    @Test func retryingAFailedJobAsksForAFreshActivity() async throws {
        let store = QueueJobStore()
        store.add(job(state: .failed, errorMessage: "Disk full"))
        let fixture = makeFixture(store: store)

        fixture.manager.retry(id: 7)
        await settle { isRunning(7, in: fixture.store) }

        // The activity of the attempt that failed is over, so the new attempt
        // gets one of its own.
        #expect(fixture.activities.starts.count == 1)
        #expect(fixture.activities.starts.first?.title == "Pokemon Red")
        #expect(fixture.activities.finishes.isEmpty)
    }

    @Test func aQueueWithoutAnyActivitiesDownloadsJustTheSame() async throws {
        let fixture = makeFixture(files: [file("red.gb", 10)])
        // The simulator and everything before iOS 26.
        fixture.activities.canShowActivities = false

        fixture.manager.enqueue(rom: rom())
        await settle { isRunning(7, in: fixture.store) }
        let jobId = try #require(fixture.store.job(romId: 7)).id
        fixture.coordinator.downloadFinished(
            key: DownloadTaskKey(jobId: jobId, fileName: "red.gb"),
            bytesOnDisk: 10
        )
        await settle { fixture.manager.finishedCount == 1 }

        #expect(fixture.manager.status(forRomId: 7) == .finished)
        #expect(fixture.finalizer.finishedRomIds == [7])
        #expect(fixture.activities.starts.isEmpty)
        #expect(fixture.activities.updates.isEmpty)
        #expect(fixture.activities.finishes.isEmpty)
    }
}
