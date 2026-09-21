import Foundation
import Observation

/// Backs the account button on Home and the sheet behind it: where the avatar
/// is loaded from, and how saving last went.
///
/// The account itself comes from `AppData`, which already holds the signed in
/// user, so nothing is fetched twice.
@Observable
@MainActor
final class AccountViewModel {

    private(set) var syncStatus: SaveSyncStatus = .off

    /// Set once the user has asked for a check, so returning to Home does not
    /// drop a fresh answer back to the older recorded run.
    private var hasCheckedThisSession = false

    private let previewUseCase: PSyncPreviewUseCase
    private let getLastRun: PGetLastSaveSyncRunUseCase
    private let syncSettings: PCloudSaveSyncSettings
    private let tokenProvider: PTokenProvider

    init(
        factory: PDependencyFactory = DefaultDependencyFactory.shared,
        syncSettings: PCloudSaveSyncSettings = CloudSaveSyncSettings.shared
    ) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.getLastRun = factory.makeGetLastSaveSyncRunUseCase()
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

    /// True while the only honest thing to show is an offer to go and look.
    var canCheckNow: Bool {
        guard reportsSyncStatus else { return false }
        if case .checking = syncStatus { return false }
        return true
    }

    /// Reads what the last finished run left behind. Local and free, so Home
    /// can call it on every appearance.
    ///
    /// Never talks to the server: negotiating opens a session server side and
    /// cancels the one an open Save Sync screen is holding, so it may only ever
    /// happen because the user asked for it. See ``checkNow()``.
    func loadRecordedStatus() {
        guard reportsSyncStatus else {
            syncStatus = .off
            return
        }
        guard !hasCheckedThisSession else { return }
        guard let run = getLastRun.execute() else {
            syncStatus = .unknown
            return
        }
        syncStatus = SaveSyncStatus(run: run)
    }

    /// Asks the server what a sync would do and turns the answer into a status.
    /// Only ever called because the user tapped for it: it is the same
    /// negotiation the Save Sync screen runs, and it is not free.
    func checkNow() async {
        guard reportsSyncStatus else {
            syncStatus = .off
            return
        }
        hasCheckedThisSession = true
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
