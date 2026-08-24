import Foundation

/// A build published to TestFlight that is newer than the installed one.
struct AvailableUpdate: Equatable, Sendable {
    let build: Int
    let version: String
    let date: String?
    /// Changelog entries newer than the installed build, newest first. Empty when
    /// the update was restored from cache and the entries were not fetched yet.
    let entries: [ChangelogEntry]
}

/// How the running app was distributed. Decides whether an update check makes
/// sense at all: App Store users get updates from the system.
enum AppDistributionChannel: Sendable {
    case debug
    case testFlight
    case appStore
}
