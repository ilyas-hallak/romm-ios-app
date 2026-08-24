import Testing
import Foundation
@testable import romm

// MARK: - Mocks

private final class MockUpdateRepository: PChangelogRepository {
    var installedBuild: Int
    var distributionChannel: AppDistributionChannel
    var publishedResult: Result<[ChangelogEntry], Error>

    init(
        installedBuild: Int,
        channel: AppDistributionChannel = .testFlight,
        published: [ChangelogEntry] = []
    ) {
        self.installedBuild = installedBuild
        self.distributionChannel = channel
        self.publishedResult = .success(published)
    }

    func bundledEntries() -> [ChangelogEntry] { [] }

    func publishedEntries() async throws -> [ChangelogEntry] {
        try publishedResult.get()
    }
}

private final class MockUpdateStateStore: PUpdateCheckStateStore {
    var lastCheckedAt: Date?
    var dismissedBuild: Int?
    var cachedPublishedBuild: Int?
    var forcesCheck: Bool

    init(forcesCheck: Bool = false) {
        self.forcesCheck = forcesCheck
    }
}

private struct TestError: Error {}

// MARK: - Tests

struct CheckForUpdateUseCaseTests {

    private func entry(build: Int, order: Int = 0) -> ChangelogEntry {
        ChangelogEntry(build: build, version: "1.0", date: nil, body: "body", order: order)
    }

    // MARK: - Distribution channel gating

    // App Store users get updates through the system. Showing a "there's an update"
    // banner would be redundant and potentially confusing - skip the check entirely.
    @Test func appStoreChannelReturnsNotChecked() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .appStore,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // Debug builds should not flood the developer with update banners; the flag
    // must be explicitly enabled before a check happens.
    @Test func debugChannelWithoutForceFlagReturnsNotChecked() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .debug,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore(forcesCheck: false)
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // The debug force flag exists exactly for QA and development testing of the
    // update flow without being on TestFlight.
    @Test func debugChannelWithForceFlagPerformsCheck() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .debug,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore(forcesCheck: true)
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        // The exact result depends on data, but it must not be notChecked.
        #expect(result != .notChecked)
    }

    @Test func testFlightChannelPerformsCheck() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result != .notChecked)
    }

    // MARK: - Throttling

    // Network traffic is wasted if we re-fetch every launch; 6 hours is the
    // minimum gap. A check done 1 hour ago must not trigger another fetch.
    @Test func recentCheckIsThrottled() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore()
        let oneHourAgo = Date().addingTimeInterval(-3600)
        store.lastCheckedAt = oneHourAgo
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // A check done exactly at the throttle boundary (6 hours + 1 second ago)
    // must be allowed through so the user does not wait forever.
    @Test func checkOlderThanThrottleWindowIsAllowed() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore()
        let justOverSixHours = Date().addingTimeInterval(-(6 * 3600 + 1))
        store.lastCheckedAt = justOverSixHours
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result != .notChecked)
    }

    // MARK: - Update detection

    @Test func newerBuildReturnsUpdateAvailable() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: [entry(build: 49, order: 0), entry(build: 48, order: 1)])
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        if case .updateAvailable(let update) = result {
            #expect(update.build == 49)
        } else {
            Issue.record("Expected updateAvailable, got \(result)")
        }
    }

    // Only entries strictly newer than the installed build should appear in the
    // banner's "what's new" list. Showing the already-installed build is noise.
    @Test func updateAvailableEntriesAreOnlyNewerThanInstalled() async {
        let published = [
            entry(build: 49, order: 0),
            entry(build: 48, order: 1),
            entry(build: 47, order: 2),
        ]
        let repo = MockUpdateRepository(installedBuild: 47, channel: .testFlight,
                                        published: published)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        if case .updateAvailable(let update) = result {
            #expect(!update.entries.contains(where: { $0.build <= 47 }))
            #expect(update.entries.contains(where: { $0.build == 48 }))
            #expect(update.entries.contains(where: { $0.build == 49 }))
        } else {
            Issue.record("Expected updateAvailable, got \(result)")
        }
    }

    @Test func sameOrOlderBuildReturnsUpToDate() async {
        let repo = MockUpdateRepository(installedBuild: 49, channel: .testFlight,
                                        published: [entry(build: 48, order: 0), entry(build: 49, order: 1)])
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .upToDate)
    }

    // MARK: - Dismissed build

    // Once the user dismisses a banner for build 49, it should not come back
    // unless an even newer build (50+) appears in the changelog.
    @Test func dismissedBuildReturnsUpToDate() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: [entry(build: 49, order: 0)])
        let store = MockUpdateStateStore()
        store.dismissedBuild = 49
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .upToDate)
    }

    // A newer build than the dismissed one lifts the dismissal automatically
    // because the user has not seen that version yet.
    @Test func newerBuildThanDismissedStillShowsBanner() async {
        let published = [entry(build: 50, order: 0), entry(build: 49, order: 1)]
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: published)
        let store = MockUpdateStateStore()
        store.dismissedBuild = 49
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        if case .updateAvailable(let update) = result {
            #expect(update.build == 50)
        } else {
            Issue.record("Expected updateAvailable, got \(result)")
        }
    }

    // MARK: - Network error handling

    // A failed network fetch must not erase an already-visible banner. Returning
    // .notChecked leaves any existing UI state unchanged.
    @Test func networkErrorReturnsNotChecked() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight)
        repo.publishedResult = .failure(TestError())
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // A failed check must not update lastCheckedAt: if we recorded the attempt,
    // the throttle would suppress the next real check for 6 hours on a bad
    // network, making the feature feel broken.
    @Test func networkErrorDoesNotUpdateLastCheckedAt() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight)
        repo.publishedResult = .failure(TestError())
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == nil)
    }

    // MARK: - State persistence after a successful check

    // After a successful fetch, both the timestamp and the cached build must be
    // written so the next launch can show the banner instantly from cache.
    @Test func successfulCheckWritesLastCheckedAt() async {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store,
                                            now: { fixedDate })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == fixedDate)
    }

    @Test func successfulCheckWritesCachedPublishedBuild() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight,
                                        published: [entry(build: 49), entry(build: 48, order: 1)])
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.cachedPublishedBuild == 49)
    }

    // Even a "up to date" check must persist the timestamp, otherwise the
    // throttle never kicks in and we keep hitting the network.
    @Test func upToDateCheckStillWritesLastCheckedAt() async {
        let fixedDate = Date(timeIntervalSince1970: 2_000_000)
        let repo = MockUpdateRepository(installedBuild: 49, channel: .testFlight,
                                        published: [entry(build: 49)])
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store,
                                            now: { fixedDate })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == fixedDate)
    }
}
