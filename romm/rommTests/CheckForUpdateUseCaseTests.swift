import Testing
import Foundation
@testable import romm

// MARK: - Mocks

private final class MockUpdateRepository: PChangelogRepository {
    var installedBuild: Int
    var distributionChannel: AppDistributionChannel
    /// Result of the "what is on main" lookup, so a test can hand over a build
    /// number or make the network leg fail.
    var publishedResult: Result<Int, Error>

    init(
        installedBuild: Int,
        channel: AppDistributionChannel = .testFlight,
        published: Int = 0
    ) {
        self.installedBuild = installedBuild
        self.distributionChannel = channel
        self.publishedResult = .success(published)
    }

    func bundledEntries() -> [ChangelogEntry] { [] }

    func latestPublishedBuild() async throws -> Int {
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

    // MARK: - Distribution channel gating

    // App Store users get updates through the system. Showing a "there's an update"
    // banner would be redundant and potentially confusing, so skip the check entirely.
    @Test func appStoreChannelReturnsNotChecked() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .appStore, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // A skipped check must leave the state untouched, otherwise the throttle would
    // start ticking for a check that never happened.
    @Test func appStoreChannelWritesNoState() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .appStore, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == nil)
        #expect(store.cachedPublishedBuild == nil)
    }

    // Debug builds should not nag the developer with update banners, so the flag
    // has to be turned on by hand before a check happens.
    @Test func debugChannelWithoutForceFlagReturnsNotChecked() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .debug, published: 49)
        let store = MockUpdateStateStore(forcesCheck: false)
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // The debug force flag exists exactly so the update flow can be exercised
    // without shipping a build to TestFlight first.
    @Test func debugChannelWithForceFlagPerformsCheck() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .debug, published: 49)
        let store = MockUpdateStateStore(forcesCheck: true)
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .updateAvailable(AvailableUpdate(build: 49)))
    }

    @Test func testFlightChannelPerformsCheck() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .updateAvailable(AvailableUpdate(build: 49)))
    }

    // MARK: - Throttling

    // Re-fetching on every launch is wasted traffic, so a check done an hour ago
    // must not trigger another one.
    @Test func recentCheckIsThrottled() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        store.lastCheckedAt = Date().addingTimeInterval(-3600)
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // Just past the six hour window the check has to run again, otherwise a user
    // who leaves the app open would never learn about a new build.
    @Test func checkOlderThanThrottleWindowIsAllowed() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        store.lastCheckedAt = Date().addingTimeInterval(-(6 * 3600 + 1))
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .updateAvailable(AvailableUpdate(build: 49)))
    }

    // MARK: - Update detection

    @Test func newerBuildReturnsUpdateAvailable() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .updateAvailable(AvailableUpdate(build: 49)))
    }

    // The number in the banner is the one from main, not a delta or an offset,
    // so a jump of several builds still names the build the tester will install.
    @Test func updateAvailableCarriesThePublishedBuildNumber() async {
        let repo = MockUpdateRepository(installedBuild: 41, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .updateAvailable(AvailableUpdate(build: 49)))
    }

    @Test func sameBuildReturnsUpToDate() async {
        let repo = MockUpdateRepository(installedBuild: 49, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .upToDate)
    }

    // Running a build newer than main happens on a local device build, and must
    // not be reported as an available update.
    @Test func olderPublishedBuildReturnsUpToDate() async {
        let repo = MockUpdateRepository(installedBuild: 50, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .upToDate)
    }

    // MARK: - Dismissed build

    // Once the user waves away build 49 it must stay gone, otherwise the banner
    // would come back on the next launch and the dismissal would mean nothing.
    @Test func dismissedBuildReturnsUpToDate() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        store.dismissedBuild = 49
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .upToDate)
    }

    // A build newer than the dismissed one lifts the dismissal by itself, since
    // the user has not been asked about that one yet.
    @Test func newerBuildThanDismissedStillShowsBanner() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 50)
        let store = MockUpdateStateStore()
        store.dismissedBuild = 49
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .updateAvailable(AvailableUpdate(build: 50)))
    }

    // A dismissal still counts as a completed check, so the cache is refreshed
    // and the banner can be restored instantly once a newer build lands.
    @Test func dismissedBuildStillWritesState() async {
        let fixedDate = Date(timeIntervalSince1970: 3_000_000)
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        store.dismissedBuild = 49
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { fixedDate })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == fixedDate)
        #expect(store.cachedPublishedBuild == 49)
    }

    // MARK: - Network error handling

    // A failed fetch must not erase a banner that is already up, so the result is
    // "did not look" rather than "nothing newer".
    @Test func networkErrorReturnsNotChecked() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight)
        repo.publishedResult = .failure(TestError())
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // Recording a failed attempt would let the throttle suppress the next real
    // check for six hours, so a flaky network would silently disable the feature.
    @Test func networkErrorDoesNotUpdateLastCheckedAt() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight)
        repo.publishedResult = .failure(TestError())
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == nil)
        #expect(store.cachedPublishedBuild == nil)
    }

    // A failed fetch must leave an earlier cached build intact, since that is what
    // keeps the banner on screen while the network is down.
    @Test func networkErrorKeepsPreviouslyCachedBuild() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight)
        repo.publishedResult = .failure(TestError())
        let store = MockUpdateStateStore()
        store.cachedPublishedBuild = 49
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.cachedPublishedBuild == 49)
    }

    // MARK: - Unreadable build number

    // A response that carries no build number means the project file moved or its
    // format changed. That is a lookup failure, not "you are up to date", so it
    // must not be mistaken for a definitive answer.
    @Test func zeroPublishedBuildReturnsNotChecked() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 0)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        let result = await useCase.execute()

        #expect(result == .notChecked)
    }

    // Caching a 0 would make the cached-update path compare against a bogus build,
    // and stamping the time would throttle away the next honest attempt.
    @Test func zeroPublishedBuildWritesNoState() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 0)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == nil)
        #expect(store.cachedPublishedBuild == nil)
    }

    // Same reasoning as above, and here a stale cache is the only thing left to
    // show the user, so it has to survive an unreadable answer.
    @Test func zeroPublishedBuildKeepsPreviouslyCachedBuild() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 0)
        let store = MockUpdateStateStore()
        store.cachedPublishedBuild = 49
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.cachedPublishedBuild == 49)
    }

    // MARK: - State persistence after a successful check

    // The timestamp drives the throttle and the cached build lets the next launch
    // show the banner before the network answers, so both have to be written.
    @Test func successfulCheckWritesLastCheckedAt() async {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000)
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { fixedDate })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == fixedDate)
    }

    @Test func successfulCheckWritesCachedPublishedBuild() async {
        let repo = MockUpdateRepository(installedBuild: 48, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { Date() })

        _ = await useCase.execute()

        #expect(store.cachedPublishedBuild == 49)
    }

    // An "up to date" answer is a completed check too. Without the timestamp the
    // throttle never engages and every launch hits the network.
    @Test func upToDateCheckStillWritesState() async {
        let fixedDate = Date(timeIntervalSince1970: 2_000_000)
        let repo = MockUpdateRepository(installedBuild: 49, channel: .testFlight, published: 49)
        let store = MockUpdateStateStore()
        let useCase = CheckForUpdateUseCase(repository: repo, stateStore: store, now: { fixedDate })

        _ = await useCase.execute()

        #expect(store.lastCheckedAt == fixedDate)
        #expect(store.cachedPublishedBuild == 49)
    }
}

// MARK: - GetCachedUpdateUseCase

struct GetCachedUpdateUseCaseTests {

    // Without an earlier check there is nothing to restore, so the banner stays
    // hidden until the first fetch comes back.
    @Test func noCachedBuildReturnsNil() {
        let repo = MockUpdateRepository(installedBuild: 48)
        let store = MockUpdateStateStore()

        #expect(GetCachedUpdateUseCase(repository: repo, stateStore: store).execute() == nil)
    }

    // The whole point of the cache is to put the banner up before the network
    // answers, so a newer cached build has to produce an update right away.
    @Test func newerCachedBuildIsRestored() {
        let repo = MockUpdateRepository(installedBuild: 48)
        let store = MockUpdateStateStore()
        store.cachedPublishedBuild = 49

        let result = GetCachedUpdateUseCase(repository: repo, stateStore: store).execute()

        #expect(result == AvailableUpdate(build: 49))
    }

    // After the user installs the update the cache still names that build, so it
    // has to be compared against the running build rather than shown blindly.
    @Test func cachedBuildEqualToInstalledReturnsNil() {
        let repo = MockUpdateRepository(installedBuild: 49)
        let store = MockUpdateStateStore()
        store.cachedPublishedBuild = 49

        #expect(GetCachedUpdateUseCase(repository: repo, stateStore: store).execute() == nil)
    }

    // A dismissal has to survive a restart, otherwise the cached build would put
    // the banner straight back on the next launch.
    @Test func dismissedCachedBuildReturnsNil() {
        let repo = MockUpdateRepository(installedBuild: 48)
        let store = MockUpdateStateStore()
        store.cachedPublishedBuild = 49
        store.dismissedBuild = 49

        #expect(GetCachedUpdateUseCase(repository: repo, stateStore: store).execute() == nil)
    }

    // Dismissing 49 must not hide 50: the dismissal is tied to one build number.
    @Test func cachedBuildNewerThanDismissedIsRestored() {
        let repo = MockUpdateRepository(installedBuild: 48)
        let store = MockUpdateStateStore()
        store.cachedPublishedBuild = 50
        store.dismissedBuild = 49

        let result = GetCachedUpdateUseCase(repository: repo, stateStore: store).execute()

        #expect(result == AvailableUpdate(build: 50))
    }
}
