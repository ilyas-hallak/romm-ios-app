import Foundation

/// A build on TestFlight that is newer than the installed one.
struct AvailableUpdate: Equatable, Sendable {
    let build: Int
}

/// Outcome of an update check. Separates "nothing newer" from "did not look", so
/// a throttled or failed check does not wipe a hint that is already on screen.
enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(AvailableUpdate)
    case upToDate
    case notChecked
}

/// How the running app was distributed. Decides whether an update check makes
/// sense at all: App Store users get updates from the system.
enum AppDistributionChannel: Sendable {
    case debug
    case testFlight
    case appStore
}

/// The handful of numbers the update hint has to remember between launches.
protocol PAppUpdateStateStore: AnyObject {
    /// Build whose changelog the user has already been shown, nil when none was.
    var lastSeenBuild: Int? { get set }
    /// When the published build was last fetched, nil when it never was.
    var lastCheckedAt: Date? { get set }
    /// Build the user waved away, so the hint stays gone until a newer one lands.
    var dismissedBuild: Int? { get set }
    /// Newest build seen in an earlier fetch, so a throttled launch can still
    /// show the hint without waiting for the network.
    var cachedPublishedBuild: Int? { get set }
    /// Debug-only switch that forces a check outside TestFlight.
    var forcesCheck: Bool { get }
}
