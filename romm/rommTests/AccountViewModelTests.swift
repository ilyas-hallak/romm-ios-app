//
//  AccountViewModelTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

/// A deterministic suspension point, so a test can observe the view model
/// while a check is still in flight.
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

private final class FakeSyncPreviewUseCase: PSyncPreviewUseCase, @unchecked Sendable {
    var result: Result<SyncPreview, Error>
    var gate: Gate?
    private(set) var callCount = 0
    init(result: Result<SyncPreview, Error>) { self.result = result }
    func execute() async throws -> SyncPreview {
        callCount += 1
        await gate?.wait()
        return try result.get()
    }
}

/// `makeSyncPreviewUseCase` has no injection parameter of its own, the base
/// factory builds it for real from other dependencies, so it is overridden here.
private final class AccountTestFactory: MockDependencyFactory {
    let previewUseCase: FakeSyncPreviewUseCase
    /// Held as the concrete type so a test can record a run mid-scenario.
    let outcomeStore: InMemorySaveSyncOutcomeStore

    init(previewResult: Result<SyncPreview, Error>, lastRun: SaveSyncOutcome? = nil) {
        self.previewUseCase = FakeSyncPreviewUseCase(result: previewResult)
        self.outcomeStore = InMemorySaveSyncOutcomeStore(outcome: lastRun)
        super.init(apiClient: FakeAPIClient())
        saveSyncOutcomeStore = outcomeStore
    }

    override func makeSyncPreviewUseCase() -> PSyncPreviewUseCase { previewUseCase }
}

private final class FakeCloudSyncSettings: PCloudSaveSyncSettings {
    var isEnabled: Bool
    init(isEnabled: Bool) { self.isEnabled = isEnabled }
}

@MainActor
struct AccountViewModelTests {

    private func makeViewModel(
        previewResult: Result<SyncPreview, Error> = .success(upToDatePlan),
        lastRun: SaveSyncOutcome? = nil,
        syncEnabled: Bool = true
    ) -> (AccountViewModel, AccountTestFactory) {
        let factory = AccountTestFactory(previewResult: previewResult, lastRun: lastRun)
        let viewModel = AccountViewModel(
            factory: factory,
            syncSettings: FakeCloudSyncSettings(isEnabled: syncEnabled)
        )
        return (viewModel, factory)
    }

    private static let upToDatePlan = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])

    // MARK: - What Home shows

    /// The whole point of the rework: Home paints the badge from what is
    /// already known, and never negotiates on its own. Negotiating opens a
    /// session on the server and cancels the one the Save Sync screen holds.
    @Test func loadingTheRecordedStatusNeverAsksTheServer() {
        let outcome = SaveSyncOutcome(date: Date(), uploaded: 1, downloaded: 0, conflicts: 0, failed: 0)
        let (viewModel, factory) = makeViewModel(lastRun: outcome)

        viewModel.loadRecordedStatus()

        #expect(viewModel.syncStatus == .synced(at: outcome.date))
        #expect(factory.previewUseCase.callCount == 0)
    }

    /// Nothing synced yet is not a failure, and must not be drawn as one.
    @Test func withNoRunRecordedTheStatusIsUnknownAndCarriesNoBadge() {
        let (viewModel, _) = makeViewModel(lastRun: nil)

        viewModel.loadRecordedStatus()

        #expect(viewModel.syncStatus == .unknown)
        #expect(viewModel.syncStatus.badgeIcon == nil)
        #expect(viewModel.reportsSyncStatus)
    }

    @Test func withSyncSwitchedOffNothingIsReportedAndNoCheckIsOffered() {
        let outcome = SaveSyncOutcome(date: Date(), uploaded: 0, downloaded: 0, conflicts: 0, failed: 2)
        let (viewModel, factory) = makeViewModel(lastRun: outcome, syncEnabled: false)

        viewModel.loadRecordedStatus()

        #expect(viewModel.syncStatus == .off)
        #expect(viewModel.syncStatus.badgeIcon == nil)
        #expect(viewModel.reportsSyncStatus == false)
        #expect(factory.previewUseCase.callCount == 0)
    }

    // MARK: - The check the user asks for

    @Test func checkingAsksTheServerAndShowsWhatItPlanned() async {
        let (viewModel, factory) = makeViewModel(previewResult: .success(Self.upToDatePlan))

        await viewModel.checkNow()

        #expect(viewModel.syncStatus == .synced(at: nil))
        #expect(factory.previewUseCase.callCount == 1)
    }

    @Test func aFailedCheckBecomesTheStatusItDescribes() async {
        let (viewModel, _) = makeViewModel(previewResult: .failure(SyncPreviewError.serverTooOld(version: "4.8.1")))

        await viewModel.checkNow()

        #expect(viewModel.syncStatus == .unavailable(
            reason: SyncPreviewError.serverTooOld(version: "4.8.1").localizedDescription
        ))
    }

    /// Coming back to Home re-reads the recorded run, which is older than the
    /// answer the user just asked for. It must not overwrite it.
    @Test func aFreshCheckSurvivesReturningToHome() async {
        let stale = SaveSyncOutcome(date: Date(timeIntervalSince1970: 0), uploaded: 0, downloaded: 0, conflicts: 0, failed: 3)
        let (viewModel, _) = makeViewModel(previewResult: .success(Self.upToDatePlan), lastRun: stale)

        await viewModel.checkNow()
        viewModel.loadRecordedStatus()

        #expect(viewModel.syncStatus == .synced(at: nil))
    }

    /// The other direction, and the one that used to be frozen out: after a
    /// check, an actual sync on the Save Sync screen records a newer run, and
    /// coming back to Home has to show that one.
    @Test func aSyncThatRunsAfterACheckTakesTheBadgeBackOver() async {
        let stale = SaveSyncOutcome(date: Date(timeIntervalSince1970: 0), uploaded: 0, downloaded: 0, conflicts: 0, failed: 3)
        let (viewModel, factory) = makeViewModel(previewResult: .success(Self.upToDatePlan), lastRun: stale)

        await viewModel.checkNow()
        let fresh = SaveSyncOutcome(date: Date().addingTimeInterval(60), uploaded: 2, downloaded: 0, conflicts: 0, failed: 0)
        factory.outcomeStore.recordRun(fresh)
        viewModel.loadRecordedStatus()

        #expect(viewModel.syncStatus == .synced(at: fresh.date))
    }

    /// The button offering a check stays on screen while one runs, greyed out,
    /// so it cannot be fired twice and does not vanish under the finger.
    @Test func whileACheckRunsItIsMarkedAsRunningAndCannotStartASecond() async {
        let gate = Gate()
        let (viewModel, factory) = makeViewModel(previewResult: .success(Self.upToDatePlan))
        factory.previewUseCase.gate = gate

        let task = Task { await viewModel.checkNow() }
        while !viewModel.isChecking { await Task.yield() }

        #expect(viewModel.syncStatus == .checking)
        await viewModel.checkNow()
        #expect(factory.previewUseCase.callCount == 1)

        await gate.open()
        await task.value
        #expect(viewModel.isChecking == false)
    }

    // MARK: - Avatar

    @Test func anAccountWithoutAnAvatarHasNoURL() {
        // The server sends an empty string rather than null for "no avatar".
        #expect(user(avatarPath: "").avatarRelativePath == nil)
        #expect(user(avatarPath: nil).avatarRelativePath == nil)
    }

    /// RomM serves avatars through the API, and the timestamp is what gets a
    /// swapped avatar past the image cache.
    @Test func anAvatarIsAddressedThroughTheAPIWithItsChangeTimestamp() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let path = try #require(user(avatarPath: "users/1/avatar.png", updatedAt: updatedAt).avatarRelativePath)

        #expect(path == "api/raw/assets/users/1/avatar.png?ts=1700000000")
    }

    private func user(avatarPath: String?, updatedAt: Date? = nil) -> User {
        User(id: 1, username: "ilyas", role: .admin, avatarPath: avatarPath, updatedAt: updatedAt)
    }
}
