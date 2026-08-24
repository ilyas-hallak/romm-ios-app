import Foundation

/// Remembers which changelog the user has already been shown, so What's New
/// appears once per update rather than on every launch.
protocol PChangelogSeenStore: AnyObject {
    /// Highest build whose changelog was shown, nil when none ever was.
    var lastSeenBuild: Int? { get set }
}

/// Throttling and dismissal state for the TestFlight update check.
protocol PUpdateCheckStateStore: AnyObject {
    /// When the changelog was last fetched, nil when it never was.
    var lastCheckedAt: Date? { get set }
    /// Build the user waved away, so the banner stays gone until a newer one lands.
    var dismissedBuild: Int? { get set }
    /// Newest build seen in an earlier fetch, used to show the banner before the
    /// network answers.
    var cachedPublishedBuild: Int? { get set }
    /// Debug-only switch that forces a check outside TestFlight.
    var forcesCheck: Bool { get }
}
