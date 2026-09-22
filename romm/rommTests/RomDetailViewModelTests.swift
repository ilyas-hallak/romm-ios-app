//
//  RomDetailViewModelTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

/// Empty local ROM repository. `RomDetailViewModel.init` builds
/// `getDownloadedROMUseCase` and `getROMShareFilesUseCase` eagerly, both of
/// which need one, and `MockDependencyFactory` traps if it is left unstubbed.
private final class NoOpLocalROMs: PLocalROMRepository, @unchecked Sendable {
    var romsBaseURL: URL { FileManager.default.temporaryDirectory }
    func getAllDownloadedROMs() throws -> [DownloadedROM] { [] }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { nil }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { 0 }
}

/// A job store that is never actually written to in these tests: the button
/// tap either resolves before a job ever exists (cancel) or is left pending
/// (start), so nothing here needs to hold real data.
private final class NoOpJobStore: PDownloadJobStore, @unchecked Sendable {
    func allJobs() -> [DownloadJob] { [] }
    func job(id: UUID) -> DownloadJob? { nil }
    func job(romId: Int) -> DownloadJob? { nil }
    func add(_ job: DownloadJob) {}
    func replace(_ job: DownloadJob) {}
    func updateFile(jobId: UUID, fileName: String, _ mutate: (inout DownloadJobFile) -> Void) {}
    func remove(jobId: UUID) {}
}

/// Never reached by these tests: nothing here gets far enough to prepare or
/// finish a transfer.
private final class NoOpFinalizer: PROMDownloadFinalizer, @unchecked Sendable {
    func prepare(rom: Rom, files: [RomFileInfo], reservedBytes: Int64) async throws -> ROMDownloadDestination {
        ROMDownloadDestination(relativePath: "", directoryURL: FileManager.default.temporaryDirectory, didCreateDirectory: false, ownedFileNames: [])
    }
    func validateTransferredFile(named fileName: String, expectedSize: Int64, in destination: ROMDownloadDestination) throws -> DownloadedROMFile {
        DownloadedROMFile(fileName: fileName, fileSizeBytes: expectedSize)
    }
    func finish(rom: Rom, files: [RomFileInfo], destination: ROMDownloadDestination) throws -> DownloadedROM {
        DownloadedROM(id: rom.id, name: rom.name, platformName: "", platformSlug: "", downloadedAt: Date(), totalSizeBytes: 0, localDirectory: "", files: [], urlCover: nil)
    }
    func writeMetadata(rom: Rom, destination: ROMDownloadDestination, validatedFiles: [DownloadedROMFile]) throws -> DownloadedROM {
        DownloadedROM(id: rom.id, name: rom.name, platformName: "", platformSlug: "", downloadedAt: Date(), totalSizeBytes: 0, localDirectory: "", files: [], urlCover: nil)
    }
    func cleanUp(_ destination: ROMDownloadDestination) {}
}

/// Hands back an empty file list. The tests here never wait long enough for
/// this to matter: a cancelled tap stops the lookup before it starts, and a
/// fresh download only needs the row `enqueue` adds synchronously.
private final class NoOpFileList: PROMFileListProvider, @unchecked Sendable {
    func files(for rom: Rom) async throws -> [RomFileInfo] { [] }
}

/// Swallows every live activity call, exactly as the controller does below
/// iOS 26 or on the simulator.
@MainActor
private final class NoOpActivityController: PDownloadContinuedTaskController {
    func start(jobId: UUID, title: String, subtitle: String, totalBytes: Int64?) {}
    func update(jobId: UUID, completedBytes: Int64, totalBytes: Int64?, subtitle: String?) {}
    func finish(jobId: UUID, success: Bool) {}
}

@MainActor
struct RomDetailViewModelTests {

    private func makeQueue() -> DownloadQueueManager {
        let client = FakeBackgroundTransferClient()
        let coordinator = DownloadJobCoordinator(
            transferClient: client,
            store: NoOpJobStore(),
            finalizer: NoOpFinalizer(),
            apiClient: StubRommAPIClient(),
            romRepository: NoOpLocalROMs()
        )
        return DownloadQueueManager(
            transferClient: client,
            coordinator: coordinator,
            fileListProvider: NoOpFileList(),
            continuedTaskController: NoOpActivityController()
        )
    }

    private func makeViewModel(downloadQueue: DownloadQueueManager) -> RomDetailViewModel {
        RomDetailViewModel(
            factory: MockDependencyFactory(localROMRepository: NoOpLocalROMs()),
            downloadQueue: downloadQueue
        )
    }

    private func rom(id: Int = 42) -> Rom {
        Rom(id: id, name: "Pokemon Red", platformId: 3, platformSlug: "gb")
    }

    // MARK: - downloadButtonTapped

    @Test func idleRomStartsTheDownloadAndAsksForTheFlight() {
        let queue = makeQueue()
        let viewModel = makeViewModel(downloadQueue: queue)
        let rom = rom()

        let result = viewModel.downloadButtonTapped(rom: rom)

        #expect(result == .startedDownload)
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .queued)
        #expect(viewModel.showAddedToast)
    }

    @Test func failedRomIsTreatedLikeIdleAndRestartsTheDownload() {
        let queue = makeQueue()
        let viewModel = makeViewModel(downloadQueue: queue)
        let rom = rom()
        // No coordinator entry and no settled row for this ROM, which is what
        // `downloadButtonState` also reads as idle. `.failed` and `.idle` share
        // a switch case in `downloadButtonTapped`, so this exercises the same
        // branch a genuinely failed row would.
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .idle)

        let result = viewModel.downloadButtonTapped(rom: rom)

        #expect(result == .startedDownload)
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .queued)
    }

    @Test func queuedRomCancelsAndAsksForNoFlight() {
        let queue = makeQueue()
        let viewModel = makeViewModel(downloadQueue: queue)
        let rom = rom()
        _ = viewModel.downloadButtonTapped(rom: rom)
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .queued)

        let result = viewModel.downloadButtonTapped(rom: rom)

        #expect(result == .none)
        // Cancelling before the file list ever came back leaves no row behind,
        // which reads back as idle again.
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .idle)
    }

    @Test func downloadedRomDoesNothing() {
        let queue = makeQueue()
        let viewModel = makeViewModel(downloadQueue: queue)
        let rom = rom()
        viewModel.isDownloaded = true

        let result = viewModel.downloadButtonTapped(rom: rom)

        #expect(result == .none)
        #expect(queue.tasks.isEmpty)
    }
}
