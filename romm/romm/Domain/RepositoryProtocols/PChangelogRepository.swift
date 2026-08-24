import Foundation

/// Access to the changelog bundled with the app, and to the build number the
/// project on `main` currently carries.
protocol PChangelogRepository {
    /// Build number of the running app, 0 when it cannot be read.
    var installedBuild: Int { get }
    /// How this build was distributed.
    var distributionChannel: AppDistributionChannel { get }
    /// Changelog bundled with this build, newest entry first.
    func bundledEntries() -> [ChangelogEntry]
    /// Build number the project on `main` is at, which is the last one uploaded
    /// to TestFlight. Throws when it cannot be read.
    func latestPublishedBuild() async throws -> Int
}
