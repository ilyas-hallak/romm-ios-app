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
    /// Minimum gap between two network fetches. The changelog changes at most a
    /// few times a week, so anything shorter is wasted traffic.
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

        let installedBuild = repository.installedBuild
        let entries: [ChangelogEntry]
        do {
            entries = try await repository.publishedEntries()
        } catch {
            logger.error("CheckForUpdate: fetch failed - \(error.localizedDescription)")
            return .notChecked
        }

        stateStore.lastCheckedAt = now()

        // Entries keep file order and summary sections carry build 0, so the newest
        // build is the highest number rather than the first entry.
        guard let publishedBuild = entries.map(\.build).max(), publishedBuild > 0 else {
            logger.info("CheckForUpdate: changelog is empty or unparseable")
            return .notChecked
        }
        stateStore.cachedPublishedBuild = publishedBuild

        guard publishedBuild > installedBuild else {
            logger.info("CheckForUpdate: no newer build (published=\(publishedBuild), installed=\(installedBuild))")
            return .upToDate
        }
        guard publishedBuild != stateStore.dismissedBuild else {
            logger.info("CheckForUpdate: build \(publishedBuild) was dismissed")
            return .upToDate
        }

        let newerEntries = entries.filter { $0.build > installedBuild }
        guard let newest = newerEntries.first ?? entries.first else { return .upToDate }

        logger.info("CheckForUpdate: build \(publishedBuild) available")
        return .updateAvailable(
            AvailableUpdate(
                build: publishedBuild,
                version: newest.version,
                date: newest.date,
                entries: newerEntries
            )
        )
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
