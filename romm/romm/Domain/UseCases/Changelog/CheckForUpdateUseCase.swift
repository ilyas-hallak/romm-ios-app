import Foundation

/// Outcome of an update check. Distinguishes "nothing newer" from "did not look",
/// so a throttled or failed check does not wipe a banner that is already up.
enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(AvailableUpdate)
    case upToDate
    case notChecked
}

protocol PCheckForUpdateUseCase {
    func execute() async -> UpdateCheckResult
}

final class CheckForUpdateUseCase: PCheckForUpdateUseCase {
    /// Minimum gap between two network fetches. A new build lands a few times a
    /// week at most, so anything shorter is wasted traffic.
    private static let throttleInterval: TimeInterval = 6 * 60 * 60

    private let repository: PChangelogRepository
    private let stateStore: PUpdateCheckStateStore
    private let now: () -> Date
    private let logger = Logger.network

    init(
        repository: PChangelogRepository,
        stateStore: PUpdateCheckStateStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.stateStore = stateStore
        self.now = now
    }

    func execute() async -> UpdateCheckResult {
        guard isCheckWorthwhile, !isThrottled else { return .notChecked }

        let publishedBuild: Int
        do {
            publishedBuild = try await repository.latestPublishedBuild()
        } catch {
            logger.error("CheckForUpdate: fetch failed - \(error.localizedDescription)")
            return .notChecked
        }

        guard publishedBuild > 0 else {
            logger.info("CheckForUpdate: no build number found on main")
            return .notChecked
        }

        stateStore.lastCheckedAt = now()
        stateStore.cachedPublishedBuild = publishedBuild

        let installedBuild = repository.installedBuild
        guard publishedBuild > installedBuild else {
            logger.info("CheckForUpdate: no newer build (published=\(publishedBuild), installed=\(installedBuild))")
            return .upToDate
        }
        guard publishedBuild != stateStore.dismissedBuild else {
            logger.info("CheckForUpdate: build \(publishedBuild) was dismissed")
            return .upToDate
        }

        logger.info("CheckForUpdate: build \(publishedBuild) available")
        return .updateAvailable(AvailableUpdate(build: publishedBuild))
    }

    // MARK: - Private

    /// App Store users get updates from the system, so the hint is TestFlight only.
    /// Debug builds check when the flag is flipped by hand, for testing.
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
