import Foundation
import Observation

/// Backs the account button on Home and the sheet behind it: where the avatar
/// is loaded from, and how the last save sync went.
///
/// The account itself comes from `AppData`, which already holds the signed in
/// user, so nothing is fetched twice.
@Observable
@MainActor
final class AccountViewModel {

    private(set) var syncStatus: SaveSyncStatus = .off

    private let previewUseCase: PSyncPreviewUseCase
    private let syncSettings: PCloudSaveSyncSettings
    private let tokenProvider: PTokenProvider

    init(
        factory: PDependencyFactory = DefaultDependencyFactory.shared,
        syncSettings: PCloudSaveSyncSettings = CloudSaveSyncSettings.shared
    ) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.syncSettings = syncSettings
        self.tokenProvider = factory.tokenProvider
    }

    /// Whether the app can say anything about syncing at all. Save sync stays
    /// out of the App Store build, and elsewhere it is opt-in.
    var reportsSyncStatus: Bool {
        #if APP_STORE
        return false
        #else
        return syncSettings.isEnabled
        #endif
    }

    /// Asks the server what a sync would do and turns the answer into a status.
    /// Nothing is changed, this is the same read-only plan the Save Sync screen
    /// shows.
    func refreshSyncStatus() async {
        guard reportsSyncStatus else {
            syncStatus = .off
            return
        }
        syncStatus = .checking
        do {
            syncStatus = SaveSyncStatus(preview: try await previewUseCase.execute())
        } catch let error as SyncPreviewError {
            syncStatus = SaveSyncStatus(error: error)
        } catch {
            syncStatus = .failed(reason: error.localizedDescription)
        }
    }

    /// The user's avatar on their own server, or nil when they have none.
    func avatarURL(for user: User?) -> String? {
        let resolver = CoverURLResolver(serverURL: tokenProvider.getServerURL())
        return resolver.absoluteURLString(for: user?.avatarRelativePath)
    }
}
