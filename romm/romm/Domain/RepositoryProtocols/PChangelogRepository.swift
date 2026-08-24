import Foundation

/// Access to the changelog, both the copy shipped inside the app and the one
/// published for the newest build.
protocol PChangelogRepository {
    /// Build number of the running app, 0 when it cannot be read.
    var installedBuild: Int { get }
    /// How this build was distributed.
    var distributionChannel: AppDistributionChannel { get }
    /// Changelog bundled with this build, newest entry first.
    func bundledEntries() -> [ChangelogEntry]
    /// Changelog published for the newest build, read from the public repository.
    func publishedEntries() async throws -> [ChangelogEntry]
}
