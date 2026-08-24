import Foundation

/// Reads the changelog bundled with this build, and the build number the project
/// on `main` carries.
///
/// The build number is what the update hint compares against. Apple exposes no
/// API for "is a newer TestFlight build available", and the App Store Connect API
/// needs a private JWT key that must never ship inside an app. `main` is the next
/// best thing: Fastlane bumps `CURRENT_PROJECT_VERSION` and pushes it as part of
/// every upload, so whatever stands there is what testers can install.
final class AppUpdateRepository: PAppUpdateRepository {

    /// Raw GitHub is public and needs no authentication.
    private static let projectFileURL = URL(string: "https://raw.githubusercontent.com/ilyas-hallak/romm-ios-app/main/romm/romm.xcodeproj/project.pbxproj")!

    /// The setting appears once per build configuration and target. They are kept
    /// in sync by the bump, so the highest one is the build.
    private static let buildNumberSetting = "CURRENT_PROJECT_VERSION = "

    private let bundle: Bundle
    private let session: URLSession
    private let logger = Logger.network

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        // Bypass URLCache so GitHub's 300 s CDN cache cannot serve a stale file forever.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    var installedBuild: Int {
        guard let raw = bundle.infoDictionary?["CFBundleVersion"] as? String else { return 0 }
        return Int(raw) ?? 0
    }

    var distributionChannel: AppDistributionChannel {
        if bundle.isDebugBuild { return .debug }
        return bundle.isTestFlightBuild ? .testFlight : .appStore
    }

    func bundledChangelog() -> String {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md") else {
            logger.warning("CHANGELOG.md not found in app bundle")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func latestPublishedBuild() async throws -> Int {
        var request = URLRequest(url: Self.projectFileURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            logger.error("AppUpdateRepository: HTTP \(http.statusCode) for the project file")
            throw AppUpdateError.notReadable
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw AppUpdateError.notReadable
        }
        return Self.buildNumber(inProjectFile: contents)
    }

    /// Exposed for tests, and because pulling the reading out keeps the network
    /// call above readable.
    ///
    /// Deliberately not a full pbxproj parse: the file is a large OpenStep plist
    /// and all we want is one integer that appears as a plain build setting.
    /// Quotes are tolerated because a hand-edited project can carry them, and
    /// getting it wrong would switch the hint off without any sign.
    static func buildNumber(inProjectFile contents: String) -> Int {
        contents
            .components(separatedBy: buildNumberSetting)
            .dropFirst()
            .compactMap { Int($0.drop { $0 == "\"" }.prefix(while: \.isNumber)) }
            .max() ?? 0
    }
}

enum AppUpdateError: Error {
    case notReadable
}
