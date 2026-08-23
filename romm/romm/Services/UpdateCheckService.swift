//
//  UpdateCheckService.swift
//  romm
//
//  Checks whether a newer TestFlight build is available by reading the public
//  CHANGELOG.md from GitHub. Apple provides no public API for TestFlight build
//  availability, and the App Store Connect API requires a private JWT key that
//  must never be bundled with the app.
//

import Foundation
import Observation

// MARK: - URL

// Raw GitHub URL is stable across branches and public without authentication.
private let changelogURL = URL(string: "https://raw.githubusercontent.com/ilyas-hallak/romm-ios-app/main/CHANGELOG.md")!

// MARK: - UpdateCheckService

@Observable
@MainActor
final class UpdateCheckService {

    static let shared = UpdateCheckService()

    // MARK: - Public State

    struct AvailableUpdate: Equatable {
        let build: Int
        let version: String
        let date: String?
        /// All changelog entries newer than the currently installed build, newest first.
        let entries: [ChangelogEntry]
    }

    var availableUpdate: AvailableUpdate?

    // MARK: - Private

    private let logger = Logger.network

    private var lastCheckKey = "lastUpdateCheckAt"
    private var dismissedBuildKey = "dismissedUpdateBuild"
    private var cachedRemoteBuildKey = "cachedRemoteBuild"
    private var forceUpdateCheckKey = "forceUpdateCheck"

    /// Minimum interval between real network requests (6 hours).
    private let throttleInterval: TimeInterval = 6 * 60 * 60

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        // Bypass URLCache so GitHub's 300 s CDN cache cannot permanently serve a stale response.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Public API

    func checkForUpdate() async {
        guard shouldRunCheck else { return }

        let localBuild = currentLocalBuild

        // Restore a previously cached result immediately so the UI can show
        // the banner without waiting for the network.
        restoreCachedUpdateIfNeeded(localBuild: localBuild)

        guard !isThrottled else {
            logger.info("UpdateCheckService: skipping network fetch, throttled")
            return
        }

        logger.info("UpdateCheckService: fetching changelog from GitHub")

        do {
            var request = URLRequest(url: changelogURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                logger.info("UpdateCheckService: HTTP \(http.statusCode)")
            }

            guard let markdown = String(data: data, encoding: .utf8) else {
                logger.error("UpdateCheckService: could not decode response as UTF-8")
                return
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            let entries = ChangelogParser.parse(markdown)
            // Entries keep file order and may include summary sections with build 0,
            // so take the highest number rather than the first entry.
            guard let remoteBuild = entries.map(\.build).max(), remoteBuild > 0 else {
                logger.info("UpdateCheckService: changelog is empty or unparseable")
                return
            }
            UserDefaults.standard.set(remoteBuild, forKey: cachedRemoteBuildKey)

            applyUpdateIfNeeded(remoteBuild: remoteBuild, entries: entries, localBuild: localBuild)
        } catch {
            logger.error("UpdateCheckService: network error - \(error.localizedDescription)")
        }
    }

    func dismissCurrentUpdate() {
        guard let update = availableUpdate else { return }
        UserDefaults.standard.set(update.build, forKey: dismissedBuildKey)
        availableUpdate = nil
        logger.info("UpdateCheckService: dismissed update build \(update.build)")
    }

    // MARK: - Helpers

    private var shouldRunCheck: Bool {
        // Always run in TestFlight.
        if Bundle.main.isTestFlightBuild { return true }

        // In Debug builds, only run when explicitly forced via UserDefaults.
        if Bundle.main.isDebugBuild {
            return UserDefaults.standard.bool(forKey: forceUpdateCheckKey)
        }

        // Release builds outside TestFlight: skip (App Store users get system updates).
        return false
    }

    private var isThrottled: Bool {
        guard let last = UserDefaults.standard.object(forKey: lastCheckKey) as? TimeInterval else {
            return false
        }
        return Date().timeIntervalSince1970 - last < throttleInterval
    }

    private var currentLocalBuild: Int {
        guard let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
              let build = Int(buildString) else {
            return 0
        }
        return build
    }

    private var dismissedBuild: Int {
        UserDefaults.standard.integer(forKey: dismissedBuildKey)
    }

    private func restoreCachedUpdateIfNeeded(localBuild: Int) {
        let cached = UserDefaults.standard.integer(forKey: cachedRemoteBuildKey)
        guard cached > localBuild, cached != dismissedBuild else { return }
        // We do not have the full entry list cached, so only show a minimal
        // placeholder. A fresh network fetch will replace it with full entries.
        if availableUpdate == nil {
            availableUpdate = AvailableUpdate(build: cached, version: "?", date: nil, entries: [])
        }
    }

    private func applyUpdateIfNeeded(remoteBuild: Int, entries: [ChangelogEntry], localBuild: Int) {
        guard remoteBuild > localBuild else {
            logger.info("UpdateCheckService: no newer build (remote=\(remoteBuild), local=\(localBuild))")
            availableUpdate = nil
            return
        }

        guard remoteBuild != dismissedBuild else {
            logger.info("UpdateCheckService: build \(remoteBuild) was dismissed by the user")
            availableUpdate = nil
            return
        }

        let newerEntries = entries.filter { $0.build > localBuild }
        let newest = newerEntries.first ?? entries[0]

        availableUpdate = AvailableUpdate(
            build: remoteBuild,
            version: newest.version,
            date: newest.date,
            entries: newerEntries
        )
        logger.info("UpdateCheckService: update available - build \(remoteBuild)")
    }
}
