import Foundation

/// The changelog shipped with the app, and the build number the project on
/// `main` currently carries.
protocol PAppUpdateRepository {
    /// Build number of the running app, 0 when it cannot be read.
    var installedBuild: Int { get }
    /// How this build was distributed.
    var distributionChannel: AppDistributionChannel { get }
    /// The bundled CHANGELOG.md, verbatim. Empty when it is missing.
    func bundledChangelog() -> String
    /// Build number the project on `main` is at, which is the last one uploaded
    /// to TestFlight. Throws when it cannot be read.
    func latestPublishedBuild() async throws -> Int
}
