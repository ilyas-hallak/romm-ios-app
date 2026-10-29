import Foundation
import Observation

/// Backs the account button on Home and the sheet behind it: where the avatar
/// is loaded from, and how saving last went.
///
/// The account itself comes from `AppData`, which already holds the signed in
/// user, so nothing is fetched twice, except the one-shot fetch after login is
/// never retried if it fails. See ``ensureCurrentUserLoaded(in:)``.
@Observable
@MainActor
final class AccountViewModel {

    private(set) var syncStatus: SaveSyncStatus = .off

    /// When the user last got an answer out of a check, so a recorded run only
    /// takes the screen back over once it is genuinely newer.
    private var lastCheckedAt: Date?

    private let previewUseCase: PSyncPreviewUseCase
    private let getLastRun: PGetLastSaveSyncRunUseCase
    private let getCurrentUserUseCase: GetCurrentUserUseCase
    private let syncSettings: PCloudSaveSyncSettings
    private let tokenProvider: PTokenProvider
    private let updateStore: AppUpdateStore

    init(
        factory: PDependencyFactory = DefaultDependencyFactory.shared,
        syncSettings: PCloudSaveSyncSettings = CloudSaveSyncSettings.shared
    ) {
        self.previewUseCase = factory.makeSyncPreviewUseCase()
        self.getLastRun = factory.makeGetLastSaveSyncRunUseCase()
        self.getCurrentUserUseCase = factory.makeGetCurrentUserUseCase()
        self.syncSettings = syncSettings
        self.tokenProvider = factory.tokenProvider
        self.updateStore = factory.appUpdateStore
    }

    /// `AppViewModel` fetches the current user exactly once, right after login,
    /// and only logs a warning if that single attempt fails, e.g. a transient
    /// blip right after a fresh device-flow pairing. Nothing retries it after
    /// that, so account-gated UI like the library scan entry can stay hidden
    /// for the rest of the session even though the account does have the
    /// scope. Home calls this on every appearance; it is a no-op once the user
    /// is actually loaded.
    func ensureCurrentUserLoaded(in appData: AppData) async {
        guard appData.currentUser == nil else { return }
        if let user = try? await getCurrentUserUseCase.execute() {
            appData.updateUser(user)
        }
    }

    /// The whole version history, for the account's Version History entry.
    var changelog: String { updateStore.changelog }

    /// Whether the app can say anything about syncing at all. Save sync stays
    /// out of the App Store build, and elsewhere it is opt-in.
    var reportsSyncStatus: Bool {
        #if APP_STORE
        return false
        #else
        return syncSettings.isEnabled
        #endif
    }

    /// True while a check is in flight, so the button offering one can stay put
    /// and grey out instead of disappearing from under the finger.
    var isChecking: Bool {
        if case .checking = syncStatus { return true }
        return false
    }

    /// Reads what the last finished run left behind. Local and free, so Home
    /// can call it on every appearance.
    ///
    /// Never talks to the server: negotiating opens a session server side and
    /// cancels the one an open Save Sync screen is holding, so it may only ever
    /// happen because the user asked for it. See ``checkNow()``.
    ///
    /// A run only takes the screen back over when it is newer than the last
    /// check. Otherwise coming back to Home would drop a just-fetched answer
    /// for an older one, and locking the screen after the first check would
    /// freeze out every real sync that follows.
    func loadRecordedStatus() {
        guard reportsSyncStatus else {
            syncStatus = .off
            return
        }
        guard let run = getLastRun.execute() else {
            // An answer from a check says more than "nothing recorded yet".
            if lastCheckedAt == nil { syncStatus = .unknown }
            return
        }
        if let lastCheckedAt, run.date <= lastCheckedAt { return }
        syncStatus = SaveSyncStatus(run: run)
    }

    /// Asks the server what a sync would do and turns the answer into a status.
    /// Only ever called because the user tapped for it: it is the same
    /// negotiation the Save Sync screen runs, and it is not free.
    func checkNow() async {
        guard reportsSyncStatus, !isChecking else { return }
        syncStatus = .checking
        do {
            syncStatus = SaveSyncStatus(preview: try await previewUseCase.execute(romIds: nil))
        } catch let error as SyncPreviewError {
            syncStatus = SaveSyncStatus(error: error)
        } catch {
            syncStatus = .failed(reason: error.localizedDescription)
        }
        // Stamped once the answer is in, so a sync finishing afterwards is the
        // newer of the two and wins in `loadRecordedStatus()`.
        lastCheckedAt = Date()
    }

    /// The user's avatar on their own server, or nil when they have none.
    func avatarURL(for user: User?) -> String? {
        let resolver = CoverURLResolver(serverURL: tokenProvider.getServerURL())
        return resolver.absoluteURLString(for: user?.avatarRelativePath)
    }
}
