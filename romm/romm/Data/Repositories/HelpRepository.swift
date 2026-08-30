import Foundation

/// Supplies the help content, preferring the copy on GitHub over the one that
/// shipped with the app.
///
/// The remote copy is the point of the whole thing: most of what users ask about
/// is already fixed or has an answer that changes, and an answer compiled into
/// the binary is stale the day it ships. Editing `FAQ.md` on `main` updates
/// every installed app.
///
/// Deliberately independent of the RomM server. Help is needed most when the
/// server cannot be reached, which is exactly when the setup screen offers it.
final class HelpRepository: PHelpRepository {

    private static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/ilyas-hallak/romm-ios-app/main/FAQ.md")!

    /// Short on purpose. Help opens on a tap, so waiting is worse than showing
    /// the bundled copy, which is never badly out of date.
    private static let timeout: TimeInterval = 5

    private let bundle: Bundle
    private let session: URLSession
    private let logger = Logger.network

    init(bundle: Bundle = .main, session: URLSession = .shared) {
        self.bundle = bundle
        self.session = session
    }

    func helpMarkdown() async -> String {
        if let remote = await fetchRemote() { return remote }
        return bundled()
    }

    private func fetchRemote() async -> String? {
        var request = URLRequest(url: Self.remoteURL)
        request.timeoutInterval = Self.timeout
        // The whole point is to see edits, so a cached copy is not good enough.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                logger.warning("HelpRepository: HTTP \(http.statusCode), falling back to the bundled help")
                return nil
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
            return text
        } catch {
            logger.info("HelpRepository: \(error.localizedDescription), falling back to the bundled help")
            return nil
        }
    }

    private func bundled() -> String {
        guard let url = bundle.url(forResource: "FAQ", withExtension: "md") else {
            logger.warning("FAQ.md not found in app bundle")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
