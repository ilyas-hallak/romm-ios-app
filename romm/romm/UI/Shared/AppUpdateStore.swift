import Foundation
import Observation

/// App-wide state for the changelog sheet and the TestFlight update hint.
///
/// The banner on Home and the row in Settings show the same thing, so the state
/// lives in one place rather than once per view. Views get it from the
/// dependency factory instead of reaching for a global.
@Observable
@MainActor
final class AppUpdateStore {

    /// A newer TestFlight build, or nil when there is none or it was dismissed.
    private(set) var availableUpdate: AvailableUpdate?
    /// True on the first launch of a build whose changelog was not shown yet.
    private(set) var shouldShowChangelog = false

    private let useCase: PAppUpdateUseCase

    /// `nonisolated` so the dependency factory can build it outside the main actor.
    nonisolated init(useCase: PAppUpdateUseCase) {
        self.useCase = useCase
    }

    var changelog: String { useCase.changelog() }

    /// Answered from disk, so the sheet can be presented without waiting for the
    /// network check below.
    func loadLocalState() {
        shouldShowChangelog = useCase.shouldShowChangelog()
    }

    func checkForUpdates() async {
        switch await useCase.checkForUpdate() {
        case .updateAvailable(let update):
            availableUpdate = update
        case .upToDate:
            availableUpdate = nil
        case .notChecked:
            // Wrong channel or nothing cached: leave whatever is on screen.
            break
        }
    }

    func markChangelogSeen() {
        useCase.markChangelogSeen()
        shouldShowChangelog = false
    }

    func dismissAvailableUpdate() {
        guard let update = availableUpdate else { return }
        useCase.dismiss(build: update.build)
        availableUpdate = nil
    }
}
