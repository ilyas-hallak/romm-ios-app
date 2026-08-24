import Foundation

/// Reads the changelog from two places: the copy bundled with this build, and
/// the one on `main` in the public repository.
///
/// The published copy is what drives the update hint. Apple exposes no API for
/// "is a newer TestFlight build available", and the App Store Connect API needs a
/// private JWT key that must never ship inside an app.
final class ChangelogRepository: PChangelogRepository {

    /// Raw GitHub is stable across branches and needs no authentication.
    private static let publishedURL = URL(string: "https://raw.githubusercontent.com/ilyas-hallak/romm-ios-app/main/CHANGELOG.md")!

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

    func bundledEntries() -> [ChangelogEntry] {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md") else {
            logger.warning("CHANGELOG.md not found in app bundle")
            return []
        }
        do {
            return ChangelogParser.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            logger.warning("Failed to read bundled CHANGELOG.md: \(error.localizedDescription)")
            return []
        }
    }

    func publishedEntries() async throws -> [ChangelogEntry] {
        var request = URLRequest(url: Self.publishedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            logger.info("ChangelogRepository: HTTP \(http.statusCode)")
        }
        guard let markdown = String(data: data, encoding: .utf8) else {
            throw ChangelogError.notReadable
        }
        return ChangelogParser.parse(markdown)
    }
}

enum ChangelogError: Error {
    case notReadable
}
