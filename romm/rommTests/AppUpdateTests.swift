import Testing
import Foundation
@testable import romm

// MARK: - Doubles

private final class MockAppUpdateRepository: PAppUpdateRepository {
    var installedBuild: Int
    var distributionChannel: AppDistributionChannel
    var changelog: String
    var published: Result<Int, Error>

    init(
        installedBuild: Int = 48,
        channel: AppDistributionChannel = .testFlight,
        changelog: String = "### Build 48\n- something",
        published: Result<Int, Error> = .success(0)
    ) {
        self.installedBuild = installedBuild
        self.distributionChannel = channel
        self.changelog = changelog
        self.published = published
    }

    func bundledChangelog() -> String { changelog }

    func latestPublishedBuild() async throws -> Int {
        try published.get()
    }
}

private final class MockStateStore: PAppUpdateStateStore {
    var lastSeenBuild: Int?
    var lastCheckedAt: Date?
    var dismissedBuild: Int?
    var cachedPublishedBuild: Int?
    var forcesCheck: Bool

    init(forcesCheck: Bool = false) {
        self.forcesCheck = forcesCheck
    }
}

private struct Boom: Error {}

private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

private func makeUseCase(
    repository: MockAppUpdateRepository,
    store: MockStateStore
) -> AppUpdateUseCase {
    AppUpdateUseCase(repository: repository, stateStore: store, now: { referenceDate })
}

// MARK: - Update check

struct AppUpdateCheckTests {

    // App Store users get updates through the system, so a hint there would point
    // at a build they cannot install.
    @Test func appStoreChannelDoesNotCheck() async {
        let repo = MockAppUpdateRepository(channel: .appStore, published: .success(49))
        let store = MockStateStore()

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate() == .notChecked)
        #expect(store.lastCheckedAt == nil)
    }

    @Test func debugChannelOnlyChecksWhenForced() async {
        let repo = MockAppUpdateRepository(channel: .debug, published: .success(49))

        let off = MockStateStore(forcesCheck: false)
        #expect(await makeUseCase(repository: repo, store: off).checkForUpdate() == .notChecked)

        let on = MockStateStore(forcesCheck: true)
        #expect(await makeUseCase(repository: repo, store: on).checkForUpdate()
                == .updateAvailable(AvailableUpdate(build: 49)))
    }

    @Test func newerBuildIsOffered() async {
        let repo = MockAppUpdateRepository(installedBuild: 48, published: .success(49))
        let store = MockStateStore()

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate()
                == .updateAvailable(AvailableUpdate(build: 49)))
        #expect(store.cachedPublishedBuild == 49)
        #expect(store.lastCheckedAt == referenceDate)
    }

    @Test(arguments: [48, 47])
    func sameOrOlderBuildIsUpToDate(published: Int) async {
        let repo = MockAppUpdateRepository(installedBuild: 48, published: .success(published))
        #expect(await makeUseCase(repository: repo, store: MockStateStore()).checkForUpdate() == .upToDate)
    }

    @Test func dismissedBuildStaysHidden() async {
        let repo = MockAppUpdateRepository(installedBuild: 48, published: .success(49))
        let store = MockStateStore()
        store.dismissedBuild = 49

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate() == .upToDate)
    }

    // A newer build than the dismissed one has to come back, otherwise waving the
    // hint away once would silence it forever.
    @Test func buildNewerThanTheDismissedOneReappears() async {
        let repo = MockAppUpdateRepository(installedBuild: 48, published: .success(50))
        let store = MockStateStore()
        store.dismissedBuild = 49

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate()
                == .updateAvailable(AvailableUpdate(build: 50)))
    }

    // Six hours between fetches, but a throttled launch still answers from the
    // last known build so the hint does not blink out of existence.
    @Test func throttledCheckAnswersFromCache() async {
        let repo = MockAppUpdateRepository(installedBuild: 48, published: .success(99))
        let store = MockStateStore()
        store.lastCheckedAt = referenceDate.addingTimeInterval(-3600)
        store.cachedPublishedBuild = 49

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate()
                == .updateAvailable(AvailableUpdate(build: 49)))
        // The fetch was skipped, so the timestamp must not move.
        #expect(store.lastCheckedAt == referenceDate.addingTimeInterval(-3600))
    }

    @Test func throttledCheckWithoutCacheReportsNotChecked() async {
        let repo = MockAppUpdateRepository(published: .success(49))
        let store = MockStateStore()
        store.lastCheckedAt = referenceDate.addingTimeInterval(-60)

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate() == .notChecked)
    }

    @Test func checkOlderThanSixHoursRunsAgain() async {
        let repo = MockAppUpdateRepository(installedBuild: 48, published: .success(49))
        let store = MockStateStore()
        store.lastCheckedAt = referenceDate.addingTimeInterval(-(6 * 3600 + 1))

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate()
                == .updateAvailable(AvailableUpdate(build: 49)))
    }

    // Offline must not clear a hint the user already saw.
    @Test func networkFailureFallsBackToCache() async {
        let repo = MockAppUpdateRepository(installedBuild: 48, published: .failure(Boom()))
        let store = MockStateStore()
        store.cachedPublishedBuild = 49

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate()
                == .updateAvailable(AvailableUpdate(build: 49)))
        #expect(store.lastCheckedAt == nil)
    }

    // An unreadable project file yields 0. Treating that as "up to date" would be
    // a lie, so nothing is written and nothing is claimed.
    @Test func unreadableBuildNumberWritesNothing() async {
        let repo = MockAppUpdateRepository(published: .success(0))
        let store = MockStateStore()

        #expect(await makeUseCase(repository: repo, store: store).checkForUpdate() == .notChecked)
        #expect(store.lastCheckedAt == nil)
        #expect(store.cachedPublishedBuild == nil)
    }

    @Test func dismissRecordsTheBuild() {
        let store = MockStateStore()
        makeUseCase(repository: MockAppUpdateRepository(), store: store).dismiss(build: 49)
        #expect(store.dismissedBuild == 49)
    }
}

// MARK: - Changelog presentation

struct AppUpdateChangelogTests {

    // A fresh install has nothing to catch up on, so it is marked as seen instead
    // of greeting the user with the full history.
    @Test func freshInstallDoesNotShowTheChangelog() {
        let repo = MockAppUpdateRepository(installedBuild: 48)
        let store = MockStateStore()

        #expect(makeUseCase(repository: repo, store: store).shouldShowChangelog() == false)
        #expect(store.lastSeenBuild == 48)
    }

    @Test func newerBuildShowsTheChangelogOnce() {
        let repo = MockAppUpdateRepository(installedBuild: 49)
        let store = MockStateStore()
        store.lastSeenBuild = 48
        let useCase = makeUseCase(repository: repo, store: store)

        #expect(useCase.shouldShowChangelog())

        useCase.markChangelogSeen()

        #expect(store.lastSeenBuild == 49)
        #expect(useCase.shouldShowChangelog() == false)
    }

    @Test func sameBuildDoesNotShowAgain() {
        let repo = MockAppUpdateRepository(installedBuild: 48)
        let store = MockStateStore()
        store.lastSeenBuild = 48

        #expect(makeUseCase(repository: repo, store: store).shouldShowChangelog() == false)
    }

    // Presenting an empty sheet is worse than presenting nothing.
    @Test func missingChangelogIsNotShown() {
        let repo = MockAppUpdateRepository(installedBuild: 49, changelog: "")
        let store = MockStateStore()
        store.lastSeenBuild = 48

        #expect(makeUseCase(repository: repo, store: store).shouldShowChangelog() == false)
    }

    @Test func changelogIsPassedThroughVerbatim() {
        let markdown = "# Changelog\n\n### Build 49\n- a change"
        let repo = MockAppUpdateRepository(changelog: markdown)

        #expect(makeUseCase(repository: repo, store: MockStateStore()).changelog() == markdown)
    }
}

// MARK: - Reading the build number out of the project file

struct ProjectFileBuildNumberTests {

    // The setting appears once per configuration and target, all bumped together.
    @Test func takesTheHighestOccurrence() {
        let contents = """
        \t\t\t\tCURRENT_PROJECT_VERSION = 41;
        \t\t\t\tCURRENT_PROJECT_VERSION = 49;
        \t\t\t\tCURRENT_PROJECT_VERSION = 41;
        """
        #expect(AppUpdateRepository.buildNumber(inProjectFile: contents) == 49)
    }

    @Test func missingSettingYieldsZero() {
        #expect(AppUpdateRepository.buildNumber(inProjectFile: "MARKETING_VERSION = 1.0;") == 0)
    }

    @Test func emptyInputYieldsZero() {
        #expect(AppUpdateRepository.buildNumber(inProjectFile: "") == 0)
    }

    // A hand-edited project can carry quotes. Failing here would switch the update
    // hint off without any sign, so the quotes are skipped.
    @Test func quotedValueIsStillRead() {
        #expect(AppUpdateRepository.buildNumber(inProjectFile: "CURRENT_PROJECT_VERSION = \"41\";") == 41)
    }

    // The realistic near miss: a different setting ending in a version number.
    @Test func similarSettingsDoNotMatch() {
        #expect(AppUpdateRepository.buildNumber(inProjectFile: "DYLIB_CURRENT_VERSION = 3;") == 0)
    }

    @Test func nonNumericValueIsIgnored() {
        #expect(AppUpdateRepository.buildNumber(inProjectFile: "CURRENT_PROJECT_VERSION = $(INHERITED);") == 0)
    }
}

// MARK: - Persistence

struct AppUpdateStateStoreTests {
    private func makeStore() -> UserDefaultsAppUpdateStateStore {
        UserDefaultsAppUpdateStateStore(userDefaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    @Test func everythingStartsUnset() {
        let store = makeStore()
        #expect(store.lastSeenBuild == nil)
        #expect(store.dismissedBuild == nil)
        #expect(store.cachedPublishedBuild == nil)
        #expect(store.lastCheckedAt == nil)
        #expect(store.forcesCheck == false)
    }

    @Test func buildNumbersSurviveANewInstance() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = UserDefaultsAppUpdateStateStore(userDefaults: defaults)
        store.lastSeenBuild = 48
        store.dismissedBuild = 49
        store.cachedPublishedBuild = 50

        let reopened = UserDefaultsAppUpdateStateStore(userDefaults: defaults)
        #expect(reopened.lastSeenBuild == 48)
        #expect(reopened.dismissedBuild == 49)
        #expect(reopened.cachedPublishedBuild == 50)
    }

    @Test func timestampSurvivesANewInstance() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = UserDefaultsAppUpdateStateStore(userDefaults: defaults)
        store.lastCheckedAt = referenceDate

        let reopened = UserDefaultsAppUpdateStateStore(userDefaults: defaults)
        #expect(reopened.lastCheckedAt == referenceDate)
    }

    // Build numbers start at 1, so a stored 0 has to read back as "not set".
    @Test func clearingReadsBackAsUnset() {
        let store = makeStore()
        store.lastSeenBuild = 48
        store.lastSeenBuild = nil
        #expect(store.lastSeenBuild == nil)
    }
}
