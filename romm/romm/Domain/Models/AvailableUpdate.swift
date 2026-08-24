import Foundation

/// A build on TestFlight that is newer than the installed one.
///
/// Only the number is needed: the hint says which build is waiting and sends the
/// user to TestFlight, which shows the release notes itself.
struct AvailableUpdate: Equatable, Sendable {
    let build: Int
}

/// How the running app was distributed. Decides whether an update check makes
/// sense at all: App Store users get updates from the system.
enum AppDistributionChannel: Sendable {
    case debug
    case testFlight
    case appStore
}
