import Foundation

protocol PAppUpdateUseCase {
    /// The bundled changelog, rendered as-is. Newest build first.
    func changelog() -> String
    /// Whether this launch is the first one on a build the user has not seen the
    /// changelog for.
    func shouldShowChangelog() -> Bool
    func markChangelogSeen()
    func checkForUpdate() async -> UpdateCheckResult
    /// Hides the hint for this build. A newer one brings it back.
    func dismiss(build: Int)
}

/// Everything the update hint and the changelog screen need.
///
/// Kept as one use case with a few operations rather than one type per verb:
/// they share the same repository and state, and splitting them produced more
/// wiring than logic.
final class AppUpdateUseCase: PAppUpdateUseCase {
    /// Minimum gap between two network fetches. A new build lands a few times a
    /// week at most, so anything shorter is wasted traffic.
    private static let throttleInterval: TimeInterval = 6 * 60 * 60

    private let repository: PAppUpdateRepository
    private let stateStore: PAppUpdateStateStore
    private let now: () -> Date
    private let logger = Logger.network

    init(
        repository: PAppUpdateRepository,
        stateStore: PAppUpdateStateStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.stateStore = stateStore
        self.now = now
    }

    // MARK: - Changelog

    func changelog() -> String {
        repository.bundledChangelog()
    }

    func shouldShowChangelog() -> Bool {
        let installed = repository.installedBuild
        guard installed > 0, !repository.bundledChangelog().isEmpty else { return false }
        // A fresh install has nothing to catch up on, so the first launch counts
        // as seen rather than greeting the user with the full history.
        guard let lastSeen = stateStore.lastSeenBuild else {
            stateStore.lastSeenBuild = installed
            return false
        }
        return installed > lastSeen
    }

    func markChangelogSeen() {
        let installed = repository.installedBuild
        guard installed > 0 else { return }
        stateStore.lastSeenBuild = installed
    }

    // MARK: - Update check

    func checkForUpdate() async -> UpdateCheckResult {
        guard isCheckWorthwhile else { return .notChecked }
        // Throttled launches answer from the last known build, so the hint shows
        // up right away instead of only every six hours.
        guard !isThrottled else { return result(for: stateStore.cachedPublishedBuild) }

        let publishedBuild: Int
        do {
            publishedBuild = try await repository.latestPublishedBuild()
        } catch {
            logger.error("AppUpdate: fetch failed - \(error.localizedDescription)")
            return result(for: stateStore.cachedPublishedBuild)
        }

        guard publishedBuild > 0 else {
            logger.info("AppUpdate: no build number found on main")
            return .notChecked
        }

        stateStore.lastCheckedAt = now()
        stateStore.cachedPublishedBuild = publishedBuild
        return result(for: publishedBuild)
    }

    func dismiss(build: Int) {
        stateStore.dismissedBuild = build
    }

    // MARK: - Private

    private func result(for publishedBuild: Int?) -> UpdateCheckResult {
        guard let publishedBuild, publishedBuild > 0 else { return .notChecked }
        guard publishedBuild > repository.installedBuild else { return .upToDate }
        guard publishedBuild != stateStore.dismissedBuild else { return .upToDate }
        return .updateAvailable(AvailableUpdate(build: publishedBuild))
    }

    /// App Store users get updates from the system, so the hint is TestFlight
    /// only. Debug builds check when the flag is flipped by hand, for testing.
    private var isCheckWorthwhile: Bool {
        switch repository.distributionChannel {
        case .testFlight: return true
        case .debug: return stateStore.forcesCheck
        case .appStore: return false
        }
    }

    private var isThrottled: Bool {
        guard let last = stateStore.lastCheckedAt else { return false }
        return now().timeIntervalSince(last) < Self.throttleInterval
    }
}
