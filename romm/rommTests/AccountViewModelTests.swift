//
//  AccountViewModelTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

private final class FakeSyncPreviewUseCase: PSyncPreviewUseCase, @unchecked Sendable {
    var result: Result<SyncPreview, Error>
    private(set) var callCount = 0
    init(result: Result<SyncPreview, Error>) { self.result = result }
    func execute() async throws -> SyncPreview {
        callCount += 1
        return try result.get()
    }
}

/// `makeSyncPreviewUseCase` has no injection parameter of its own, the base
/// factory builds it for real from other dependencies, so it is overridden here.
private final class AccountTestFactory: MockDependencyFactory {
    let previewUseCase: FakeSyncPreviewUseCase

    init(previewResult: Result<SyncPreview, Error>) {
        self.previewUseCase = FakeSyncPreviewUseCase(result: previewResult)
        super.init(apiClient: FakeAPIClient())
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
        previewResult: Result<SyncPreview, Error>,
        syncEnabled: Bool = true
    ) -> (AccountViewModel, AccountTestFactory) {
        let factory = AccountTestFactory(previewResult: previewResult)
        let viewModel = AccountViewModel(
            factory: factory,
            syncSettings: FakeCloudSyncSettings(isEnabled: syncEnabled)
        )
        return (viewModel, factory)
    }

    @Test func aLoadedPlanBecomesTheStatusOnTheAccountButton() async {
        let plan = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let (viewModel, _) = makeViewModel(previewResult: .success(plan))

        await viewModel.refreshSyncStatus()

        #expect(viewModel.syncStatus == .synced)
    }

    @Test func aFailedNegotiationBecomesTheStatusItDescribes() async {
        let (viewModel, _) = makeViewModel(previewResult: .failure(SyncPreviewError.serverTooOld(version: "4.8.1")))

        await viewModel.refreshSyncStatus()

        #expect(viewModel.syncStatus == .unavailable(
            reason: SyncPreviewError.serverTooOld(version: "4.8.1").localizedDescription
        ))
    }

    /// Negotiating reports every battery save on the device, so a user who
    /// never switched sync on must not pay for a request they cannot use.
    @Test func withSyncSwitchedOffTheServerIsNeverAsked() async {
        let plan = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let (viewModel, factory) = makeViewModel(previewResult: .success(plan), syncEnabled: false)

        await viewModel.refreshSyncStatus()

        #expect(viewModel.syncStatus == .off)
        #expect(factory.previewUseCase.callCount == 0)
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
