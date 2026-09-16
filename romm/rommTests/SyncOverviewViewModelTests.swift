//
//  SyncOverviewViewModelTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

// `SyncOverviewViewModel.init` eagerly builds `getDownloadedROM` and
// `scanExternalSaves`, both of which need a `localROMRepository`.
// `MockDependencyFactory` traps if that is left unstubbed, so every test
// here must inject something, even though these tests never read from it.
private final class FakeLocalROMs: PLocalROMRepository, @unchecked Sendable {
    var romsBaseURL: URL { FileManager.default.temporaryDirectory }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { [] }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { nil }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { 0 }
}

// MARK: - Fakes for `syncNow()` / `load()`

/// Scriptable stand-in for negotiate: `load()` only ever needs to be steered
/// towards success or one particular failure, never a real network call.
private final class FakeSyncPreviewUseCase: PSyncPreviewUseCase, @unchecked Sendable {
    var result: Result<SyncPreview, Error>
    init(result: Result<SyncPreview, Error>) { self.result = result }
    func execute() async throws -> SyncPreview { try result.get() }
}

/// A deterministic suspension point so a test can observe `isSyncing` and
/// `canSyncNow` mid-run, before letting the run actually finish.
private actor Gate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// Session completion runs last in `SaveSyncRunner.run` (see its doc
/// comment), so gating it here is a suspension point that sits squarely
/// inside "the run is still in flight".
private final class GatedCompleteSyncSessionUseCase: PCompleteSyncSessionUseCase, @unchecked Sendable {
    private let gate: Gate
    private(set) var callCount = 0
    init(gate: Gate) { self.gate = gate }
    func execute(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {
        callCount += 1
        await gate.wait()
    }
}

private final class NoopCompleteSyncSessionUseCase: PCompleteSyncSessionUseCase, @unchecked Sendable {
    func execute(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {}
}

/// Lets a test throw for `listServerStatesUseCase` on demand, to reach
/// `runStatesSync`'s failure path.
private final class ControllableListServerStatesUseCase: PListServerStatesUseCase, @unchecked Sendable {
    var error: Error?
    func execute(romId: Int) async throws -> [StateSchema] { if let error { throw error }; return [] }
}

private final class SucceedingUploadSaveUseCase: PUploadSaveUseCase, @unchecked Sendable {
    private var nextId = 9000
    func execute(
        romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?,
        autocleanup: Bool?, fileName: String, fileData: Data, screenshotData: Data?
    ) async throws -> SaveSchema {
        nextId += 1
        return SaveSchema(
            id: nextId, romId: romId, userId: 1, fileName: fileName, fileNameNoTags: fileName,
            fileNameNoExt: fileName, fileExtension: "sav", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: Date(),
            updatedAt: Date(), emulator: nil, screenshot: nil, slot: slot, contentHash: nil
        )
    }
}

// None of these tests exercise these paths given the plans and stores they
// build; trapping on a call would fail the test loudly rather than silently
// accepting an unplanned operation.
private final class UnusedUploadSaveUseCase: PUploadSaveUseCase, @unchecked Sendable {
    func execute(
        romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?,
        autocleanup: Bool?, fileName: String, fileData: Data, screenshotData: Data?
    ) async throws -> SaveSchema {
        fatalError("not used in these tests")
    }
}
private final class UnusedDownloadSaveUseCase: PDownloadSaveUseCase, @unchecked Sendable {
    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data {
        fatalError("not used in these tests")
    }
}
private final class UnusedConfirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase, @unchecked Sendable {
    func execute(id: Int, deviceId: String) async throws -> SaveSchema {
        fatalError("not used in these tests")
    }
}
private final class UnusedListServerSavesUseCase: PListServerSavesUseCase, @unchecked Sendable {
    func execute(romId: Int) async throws -> [SaveSchema] {
        fatalError("not used in these tests")
    }
}
private final class UnusedUploadStateUseCase: PUploadStateUseCase, @unchecked Sendable {
    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}
private final class UnusedUpdateStateUseCase: PUpdateStateUseCase, @unchecked Sendable {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}
private final class UnusedDownloadStateUseCase: PDownloadStateUseCase, @unchecked Sendable {
    func execute(id: Int) async throws -> Data {
        fatalError("not used in these tests")
    }
}
private final class NoopExternalSaveFolderStore: PExternalSaveFolderStore, @unchecked Sendable {
    func remember(folderURL: URL, for emulator: ExternalEmulatorID) throws {}
    func grantedFolder(for emulator: ExternalEmulatorID) -> ExternalSaveFolderGrant? { nil }
    func forget(_ emulator: ExternalEmulatorID) {}
    func grantedEmulators() -> [ExternalEmulatorID] { [] }
}

/// Overrides just the two factory methods `SyncOverviewViewModel` needs
/// beyond what the base `MockDependencyFactory` already stubs: the runner is
/// a concrete `final class`, so it is built for real here from fakes this
/// file controls, rather than faked itself.
private final class SyncTestFactory: MockDependencyFactory {
    private let previewResult: Result<SyncPreview, Error>
    private let runner: SaveSyncRunner

    init(localROMRepository: PLocalROMRepository, previewResult: Result<SyncPreview, Error>, runner: SaveSyncRunner) {
        self.previewResult = previewResult
        self.runner = runner
        super.init(apiClient: FakeAPIClient(), localROMRepository: localROMRepository)
    }

    override func makeSyncPreviewUseCase() -> PSyncPreviewUseCase {
        FakeSyncPreviewUseCase(result: previewResult)
    }

    @MainActor override func makeSaveSyncRunner() -> SaveSyncRunner { runner }
}

@MainActor
struct SyncOverviewViewModelTests {

    private func makeViewModel(showing state: SyncOverviewViewModel.State) -> SyncOverviewViewModel {
        SyncOverviewViewModel(
            showing: state,
            factory: MockDependencyFactory(apiClient: FakeAPIClient(), localROMRepository: FakeLocalROMs())
        )
    }

    private func makeSyncStore() -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncOverviewViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return LocalSaveStoreRepository(rootDirectory: tmp)
    }

    private func makeRunner(
        store: PSaveStore,
        uploadSave: PUploadSaveUseCase = UnusedUploadSaveUseCase(),
        listStates: PListServerStatesUseCase = ControllableListServerStatesUseCase(),
        completeSession: PCompleteSyncSessionUseCase = NoopCompleteSyncSessionUseCase()
    ) -> SaveSyncRunner {
        SaveSyncRunner(
            saveStore: store,
            uploadSaveUseCase: uploadSave,
            downloadSaveUseCase: UnusedDownloadSaveUseCase(),
            confirmSaveDownloadUseCase: UnusedConfirmSaveDownloadUseCase(),
            listServerSavesUseCase: UnusedListServerSavesUseCase(),
            listServerStatesUseCase: listStates,
            uploadStateUseCase: UnusedUploadStateUseCase(),
            updateStateUseCase: UnusedUpdateStateUseCase(),
            downloadStateUseCase: UnusedDownloadStateUseCase(),
            completeSyncSessionUseCase: completeSession,
            externalSaveFolderStore: NoopExternalSaveFolderStore()
        )
    }

    /// `SaveSyncRunner.run` always syncs save states for every ROM this
    /// device holds anything for, regardless of what the plan says (states
    /// are never part of it, see `SyncPreviewUseCase`). A battery-only plan
    /// that is already up to date, with no matching external file either,
    /// must still leave the button enabled: a run can still find state work.
    @Test func canSyncNowIsTrueForAnUpToDatePlanWithNoExternalMatches() {
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let vm = makeViewModel(showing: .loaded(preview))

        #expect(preview.isUpToDate)
        #expect(vm.canSyncNow)
    }

    @Test func canSyncNowIsFalseWithoutALoadedPlan() {
        #expect(makeViewModel(showing: .idle).canSyncNow == false)
        #expect(makeViewModel(showing: .loading).canSyncNow == false)
        #expect(makeViewModel(showing: .failed(.notConnected)).canSyncNow == false)
    }

    // MARK: - syncNow()

    /// The button drives the runner, which drives the report and, through the
    /// reload at the end of `syncNow`, the state too. `isSyncing` and
    /// `canSyncNow` must reflect the run while it is actually in flight, not
    /// just before it starts and after it ends.
    @Test func syncNowRunsTheRunnerAndTogglesIsSyncingWhileItRuns() async throws {
        let store = makeSyncStore()
        let gate = Gate()
        let completeSession = GatedCompleteSyncSessionUseCase(gate: gate)
        let runner = makeRunner(store: store, completeSession: completeSession)
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [], sessionId: "session-1")
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), runner: runner)
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        #expect(vm.canSyncNow)

        let task = Task { await vm.syncNow() }
        while completeSession.callCount == 0 { await Task.yield() }

        #expect(vm.isSyncing)
        #expect(vm.canSyncNow == false)

        await gate.open()
        await task.value

        #expect(vm.isSyncing == false)
        #expect(vm.lastSyncReport == SaveSyncReport())
        guard case .loaded = vm.state else {
            Issue.record("expected the reload at the end of syncNow to leave the screen .loaded")
            return
        }
    }

    /// `SaveSyncRunner.run` never literally throws (see its signature); a
    /// backend hiccup instead shows up as a failure inside the returned
    /// report. That failure must still land visibly on the screen, and the
    /// run must leave the view model in a normal, still-usable state
    /// afterwards rather than getting stuck mid-sync.
    @Test func syncNowSurfacesARunFailureAndStillLeavesTheScreenUsable() async throws {
        let store = makeSyncStore()
        try store.writeState(romId: 5, slot: 0, data: Data([0x01]))
        let listStates = ControllableListServerStatesUseCase()
        listStates.error = URLError(.notConnectedToInternet)
        let runner = makeRunner(store: store, listStates: listStates)
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), runner: runner)
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        await vm.syncNow()

        #expect(vm.isSyncing == false)
        #expect(vm.lastSyncReport?.failed == 1)
        #expect(vm.lastSyncSummary?.contains("1 failed") == true)
        // The reload succeeded (the preview use case is still stubbed to
        // succeed), so the screen is back to a normal, syncable state.
        #expect(vm.canSyncNow)
    }

    // MARK: - load()

    @Test func loadSucceedsAndPopulatesStateFromThePreview() async throws {
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(
            localROMRepository: FakeLocalROMs(), previewResult: .success(preview), runner: makeRunner(store: makeSyncStore())
        )
        let vm = SyncOverviewViewModel(showing: .idle, factory: factory)

        await vm.load()

        guard case .loaded(let loaded) = vm.state else {
            Issue.record("expected .loaded")
            return
        }
        #expect(loaded.deviceId == "d1")
    }

    /// A `SyncPreviewError` is a state the screen already knows how to
    /// explain on its own terms (see the enum's cases), so it must reach
    /// `state` unchanged rather than being wrapped again.
    @Test func loadReflectsASyncPreviewErrorDirectly() async throws {
        let factory = SyncTestFactory(
            localROMRepository: FakeLocalROMs(),
            previewResult: .failure(SyncPreviewError.serverTooOld(version: "4.9.0")),
            runner: makeRunner(store: makeSyncStore())
        )
        let vm = SyncOverviewViewModel(showing: .idle, factory: factory)

        await vm.load()

        guard case .failed(let error) = vm.state else {
            Issue.record("expected .failed")
            return
        }
        #expect(error == .serverTooOld(version: "4.9.0"))
    }

    /// Anything else (a plain network error, say) has no case of its own, so
    /// it is wrapped into `.negotiationFailed` carrying the original message,
    /// unlike a `SyncPreviewError` which passes straight through untouched.
    @Test func loadWrapsAGenericErrorAsANegotiationFailure() async throws {
        struct SomeError: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        let factory = SyncTestFactory(
            localROMRepository: FakeLocalROMs(), previewResult: .failure(SomeError()), runner: makeRunner(store: makeSyncStore())
        )
        let vm = SyncOverviewViewModel(showing: .idle, factory: factory)

        await vm.load()

        guard case .failed(let error) = vm.state else {
            Issue.record("expected .failed")
            return
        }
        #expect(error == .negotiationFailed("boom"))
    }

    // MARK: - lastSyncSummary

    @Test func lastSyncSummarySaysNothingToSyncWhenAllCountersAreZero() async throws {
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(
            localROMRepository: FakeLocalROMs(), previewResult: .success(preview), runner: makeRunner(store: makeSyncStore())
        )
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        await vm.syncNow()

        #expect(vm.lastSyncSummary == "Nothing to sync, everything is up to date.")
    }

    /// A run rarely does just one kind of thing: this mixes an upload, a
    /// conflict left for the user, and a failure into one report, and checks
    /// that the summary mentions all three rather than only the first match.
    @Test func lastSyncSummaryDescribesAMixOfOutcomes() async throws {
        let store = makeSyncStore()
        try store.writeBattery(romId: 1, data: Data([0xCA]))
        try store.writeState(romId: 5, slot: 0, data: Data([0x01]))
        let listStates = ControllableListServerStatesUseCase()
        listStates.error = URLError(.notConnectedToInternet)
        let runner = makeRunner(store: store, uploadSave: SucceedingUploadSaveUseCase(), listStates: listStates)

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 1,
            operations: [
                SyncPreviewOperation(romId: 1, direction: .upload, serverFileName: nil, slot: nil, emulator: nil, reason: nil, serverUpdatedAt: nil),
                SyncPreviewOperation(romId: 9, direction: .conflict, serverFileName: nil, slot: nil, emulator: nil, reason: "Both sides changed", serverUpdatedAt: nil)
            ]
        )
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), runner: runner)
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        await vm.syncNow()

        let report = try #require(vm.lastSyncReport)
        #expect(report.uploaded == 1)
        #expect(report.skippedConflicts == 1)
        #expect(report.failed == 1)

        let summary = try #require(vm.lastSyncSummary)
        #expect(summary.contains("1 uploaded"))
        #expect(summary.contains("1 conflicts left"))
        #expect(summary.contains("1 failed"))
    }
}
