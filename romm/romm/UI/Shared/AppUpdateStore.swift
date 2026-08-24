import Foundation
import Observation

/// App-wide state for the What's New sheet and the TestFlight update hint.
///
/// The banner on Home and the row in Settings show the same thing, so the state
/// lives in one place rather than once per view. Views get it from the
/// dependency factory instead of reaching for a global.
@Observable
@MainActor
final class AppUpdateStore {

    /// A newer TestFlight build, or nil when there is none or it was dismissed.
    private(set) var availableUpdate: AvailableUpdate?
    /// Entries to show on this launch, empty when the user is up to date.
    private(set) var whatsNewEntries: [ChangelogEntry] = []

    var shouldShowWhatsNew: Bool { !whatsNewEntries.isEmpty }

    private let getWhatsNew: PGetWhatsNewUseCase
    private let getChangelog: PGetChangelogUseCase
    private let markChangelogSeen: PMarkChangelogSeenUseCase
    private let checkForUpdate: PCheckForUpdateUseCase
    private let getCachedUpdate: PGetCachedUpdateUseCase
    private let dismissUpdate: PDismissUpdateUseCase

    /// `nonisolated` so the dependency factory can build it outside the main actor.
    nonisolated init(
        getWhatsNew: PGetWhatsNewUseCase,
        getChangelog: PGetChangelogUseCase,
        markChangelogSeen: PMarkChangelogSeenUseCase,
        checkForUpdate: PCheckForUpdateUseCase,
        getCachedUpdate: PGetCachedUpdateUseCase,
        dismissUpdate: PDismissUpdateUseCase
    ) {
        self.getWhatsNew = getWhatsNew
        self.getChangelog = getChangelog
        self.markChangelogSeen = markChangelogSeen
        self.checkForUpdate = checkForUpdate
        self.getCachedUpdate = getCachedUpdate
        self.dismissUpdate = dismissUpdate
    }

    /// Everything that can be answered from disk. Kept separate from the network
    /// check so What's New can be presented immediately on launch.
    func loadLocalState() {
        whatsNewEntries = getWhatsNew.execute()
        // The last known result, so the banner does not wait for a round trip.
        availableUpdate = getCachedUpdate.execute()
    }

    /// Asks GitHub whether a newer build has been published.
    func checkForUpdates() async {
        switch await checkForUpdate.execute() {
        case .updateAvailable(let update):
            availableUpdate = update
        case .upToDate:
            availableUpdate = nil
        case .notChecked:
            // Throttled, wrong channel or offline: keep whatever is on screen.
            break
        }
    }

    /// The full version history, for the Settings entry.
    func versionHistory() -> [ChangelogEntry] {
        getChangelog.execute()
    }

    func markWhatsNewSeen() {
        markChangelogSeen.execute()
        whatsNewEntries = []
    }

    func dismissAvailableUpdate() {
        guard let update = availableUpdate else { return }
        dismissUpdate.execute(build: update.build)
        availableUpdate = nil
    }
}
