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

    private func makeQueue(store: QueueJobStore = QueueJobStore()) -> DownloadQueueManager {
        let client = FakeBackgroundTransferClient()
        let coordinator = DownloadJobCoordinator(
            transferClient: client,
            store: store,
            finalizer: NoOpFinalizer(),
            apiClient: DownloadRequestAPIClient(),
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

    /// Lets a job's own async retry/restart run until the store shows what the
    /// test is waiting for. Nothing here awaits anything real, so yielding is
    /// enough and the test never has to sleep.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
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

    @Test func failedRomRestartsTheDownload() async throws {
        let store = QueueJobStore()
        store.add(job(romId: 42, name: "Pokemon Red", state: .failed, errorMessage: "Disk full"))
        let queue = makeQueue(store: store)
        let viewModel = makeViewModel(downloadQueue: queue)
        let rom = rom()
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .failed)

        let result = viewModel.downloadButtonTapped(rom: rom)

        #expect(result == .startedDownload)
        // The retry runs on a task of its own, so the store only shows it once
        // that task has had a chance to run.
        await settle { store.job(romId: rom.id)?.state == .running }
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .downloading(0, nil))
    }

    @Test func downloadingRomCancelsAndAsksForNoFlight() {
        let store = QueueJobStore()
        store.add(job(romId: 42, name: "Pokemon Red", state: .running, receivedBytes: 40))
        let queue = makeQueue(store: store)
        let viewModel = makeViewModel(downloadQueue: queue)
        let rom = rom()
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .downloading(0.4, nil))

        let result = viewModel.downloadButtonTapped(rom: rom)

        #expect(result == .ignored)
        // Cancelling a download that is already under way gives back its bytes
        // and drops the job, leaving a settled row that reads back as idle.
        #expect(store.job(romId: rom.id) == nil)
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .idle)
    }

    @Test func queuedRomCancelsAndAsksForNoFlight() {
        let queue = makeQueue()
        let viewModel = makeViewModel(downloadQueue: queue)
        let rom = rom()
        _ = viewModel.downloadButtonTapped(rom: rom)
        #expect(viewModel.downloadButtonState(forRomId: rom.id) == .queued)

        let result = viewModel.downloadButtonTapped(rom: rom)

        #expect(result == .ignored)
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

        #expect(result == .ignored)
        #expect(queue.tasks.isEmpty)
    }
}
