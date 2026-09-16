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

/// Fake for `PSaveSyncRunner`, the one thing `SyncOverviewViewModel` needs
/// beyond what `MockDependencyFactory` already stubs. Lets a test script the
/// report a run produces and, via an optional `Gate`, hold a run open long
/// enough to observe `isSyncing` mid-flight, or to check that a second
/// `syncNow()` never starts a second run while the first is still going.
@MainActor
private final class FakeSaveSyncRunner: PSaveSyncRunner {
    var reportToReturn = SaveSyncReport()
    var gate: Gate?
    private(set) var callCount = 0

    func run(preview: SyncPreview, externalScans: [ExternalEmulatorID: ExternalSaveScan]) async -> SaveSyncReport {
        callCount += 1
        await gate?.wait()
        return reportToReturn
    }
}

/// Overrides the one factory method `SyncOverviewViewModel` needs beyond what
/// `MockDependencyFactory` already supports via injection: `makeSyncPreviewUseCase`
/// has no injection parameter of its own, since the base factory builds it for
/// real from other dependencies rather than taking it in through `init`.
private final class SyncTestFactory: MockDependencyFactory {
    private let previewResult: Result<SyncPreview, Error>

    init(localROMRepository: PLocalROMRepository, previewResult: Result<SyncPreview, Error>, saveSyncRunner: PSaveSyncRunner) {
        self.previewResult = previewResult
        super.init(apiClient: FakeAPIClient(), localROMRepository: localROMRepository, saveSyncRunner: saveSyncRunner)
    }

    override func makeSyncPreviewUseCase() -> PSyncPreviewUseCase {
        FakeSyncPreviewUseCase(result: previewResult)
    }
}

@MainActor
struct SyncOverviewViewModelTests {

    private func makeViewModel(showing state: SyncOverviewViewModel.State) -> SyncOverviewViewModel {
        SyncOverviewViewModel(
            showing: state,
            factory: MockDependencyFactory(apiClient: FakeAPIClient(), localROMRepository: FakeLocalROMs())
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
        let gate = Gate()
        let runner = FakeSaveSyncRunner()
        runner.gate = gate
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [], sessionId: "session-1")
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: runner)
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        #expect(vm.canSyncNow)

        let task = Task { await vm.syncNow() }
        while runner.callCount == 0 { await Task.yield() }

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

    /// A second `syncNow()` call while the first is still running must not
    /// start the runner a second time (see the `isSyncing` guard in
    /// `syncNow()`). Only honestly testable now that the runner itself is a
    /// fake this file controls, rather than a concrete type reachable only
    /// through a gate buried in one of its internal use cases.
    @Test func syncNowIgnoresASecondCallWhileTheFirstIsStillRunning() async throws {
        let gate = Gate()
        let runner = FakeSaveSyncRunner()
        runner.gate = gate
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: runner)
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        let firstRun = Task { await vm.syncNow() }
        while runner.callCount == 0 { await Task.yield() }

        await vm.syncNow()
        #expect(runner.callCount == 1)

        await gate.open()
        await firstRun.value

        #expect(runner.callCount == 1)
    }

    /// `SaveSyncRunner.run` never literally throws (see its signature); a
    /// backend hiccup instead shows up as a failure inside the returned
    /// report. That failure must still land visibly on the screen, and the
    /// run must leave the view model in a normal, still-usable state
    /// afterwards rather than getting stuck mid-sync.
    @Test func syncNowSurfacesARunFailureAndStillLeavesTheScreenUsable() async throws {
        let runner = FakeSaveSyncRunner()
        runner.reportToReturn = SaveSyncReport(failed: 1, errors: ["ROM 5 slot 0: state download failed"])
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: runner)
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
            localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: FakeSaveSyncRunner()
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
            saveSyncRunner: FakeSaveSyncRunner()
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
            localROMRepository: FakeLocalROMs(), previewResult: .failure(SomeError()), saveSyncRunner: FakeSaveSyncRunner()
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
            localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: FakeSaveSyncRunner()
        )
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        await vm.syncNow()

        #expect(vm.lastSyncSummary == "Nothing to sync, everything is up to date.")
    }

    /// A run rarely does just one kind of thing: this mixes an upload, a
    /// conflict left for the user, and a failure into one report, and checks
    /// that the summary mentions all three rather than only the first match.
    @Test func lastSyncSummaryDescribesAMixOfOutcomes() async throws {
        let runner = FakeSaveSyncRunner()
        runner.reportToReturn = SaveSyncReport(uploaded: 1, skippedConflicts: 1, failed: 1, errors: ["boom"])
        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 1,
            operations: [
                SyncPreviewOperation(romId: 1, direction: .upload, serverFileName: nil, slot: nil, emulator: nil, reason: nil, serverUpdatedAt: nil),
                SyncPreviewOperation(romId: 9, direction: .conflict, serverFileName: nil, slot: nil, emulator: nil, reason: "Both sides changed", serverUpdatedAt: nil)
            ]
        )
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: runner)
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

    // MARK: - lastSyncErrors

    @Test func lastSyncErrorsIsEmptyWhenTheRunHadNoFailures() async throws {
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(
            localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: FakeSaveSyncRunner()
        )
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        await vm.syncNow()

        #expect(vm.lastSyncErrors.isEmpty)
    }

    @Test func lastSyncErrorsShowsAllOfThemUpToThree() async throws {
        let runner = FakeSaveSyncRunner()
        runner.reportToReturn = SaveSyncReport(failed: 3, errors: ["error 1", "error 2", "error 3"])
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: runner)
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        await vm.syncNow()

        #expect(vm.lastSyncErrors == ["error 1", "error 2", "error 3"])
    }

    /// More than three failures would otherwise flood the screen, so the list
    /// is capped with a trailing "and N more" line rather than shown in full.
    @Test func lastSyncErrorsCapsAtThreeWithAnAndMoreLine() async throws {
        let runner = FakeSaveSyncRunner()
        let errors = (1...7).map { "error \($0)" }
        runner.reportToReturn = SaveSyncReport(failed: 7, errors: errors)
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let factory = SyncTestFactory(localROMRepository: FakeLocalROMs(), previewResult: .success(preview), saveSyncRunner: runner)
        let vm = SyncOverviewViewModel(showing: .loaded(preview), factory: factory)

        await vm.syncNow()

        #expect(vm.lastSyncErrors == ["error 1", "error 2", "error 3", "and 4 more"])
    }
}
