import Testing
import Foundation
@testable import romm

// MARK: - Mocks

private final class MockChangelogRepository: PChangelogRepository {
    var installedBuild: Int
    var distributionChannel: AppDistributionChannel = .testFlight
    var bundled: [ChangelogEntry]

    init(installedBuild: Int, bundled: [ChangelogEntry] = []) {
        self.installedBuild = installedBuild
        self.bundled = bundled
    }

    func bundledEntries() -> [ChangelogEntry] { bundled }
    func publishedEntries() async throws -> [ChangelogEntry] { [] }
}

private final class MockChangelogSeenStore: PChangelogSeenStore {
    var lastSeenBuild: Int?
    init(lastSeenBuild: Int? = nil) { self.lastSeenBuild = lastSeenBuild }
}

// MARK: - Tests

struct GetWhatsNewUseCaseTests {

    // Convenience: build a numbered entry that is easy to reason about in assertions.
    private func entry(build: Int, order: Int = 0) -> ChangelogEntry {
        ChangelogEntry(build: build, version: "1.0", date: nil, body: "body \(build)", order: order)
    }

    // MARK: - Fresh install

    // On a fresh install lastSeenBuild is nil, so the "what's new" sheet would be
    // enormous if we showed every entry. Only the current build's entry is shown.
    @Test func freshInstallShowsOnlyInstalledBuildEntry() {
        let entries = [entry(build: 49, order: 0), entry(build: 48, order: 1), entry(build: 47, order: 2)]
        let repo = MockChangelogRepository(installedBuild: 49, bundled: entries)
        let seen = MockChangelogSeenStore(lastSeenBuild: nil)
        let useCase = GetWhatsNewUseCase(repository: repo, seenStore: seen)

        let result = useCase.execute()

        #expect(result.count == 1)
        #expect(result[0].build == 49)
    }

    // If the installed build has no matching entry in the bundled changelog the
    // fresh-install path returns nothing rather than showing unrelated content.
    @Test func freshInstallWithNoMatchingEntryReturnsEmpty() {
        let entries = [entry(build: 47, order: 0), entry(build: 46, order: 1)]
        let repo = MockChangelogRepository(installedBuild: 49, bundled: entries)
        let seen = MockChangelogSeenStore(lastSeenBuild: nil)
        let useCase = GetWhatsNewUseCase(repository: repo, seenStore: seen)

        let result = useCase.execute()

        #expect(result.isEmpty)
    }

    // MARK: - After an update

    // After updating from build 47 to 49, the user should see 48 and 49 but
    // not 47 or older - only entries strictly newer than what they last saw.
    @Test func afterUpdateShowsEntriesNewerThanLastSeen() {
        let entries = [
            entry(build: 49, order: 0),
            entry(build: 48, order: 1),
            entry(build: 47, order: 2),
        ]
        let repo = MockChangelogRepository(installedBuild: 49, bundled: entries)
        let seen = MockChangelogSeenStore(lastSeenBuild: 47)
        let useCase = GetWhatsNewUseCase(repository: repo, seenStore: seen)

        let result = useCase.execute()

        #expect(result.count == 2)
        #expect(result.contains(where: { $0.build == 49 }))
        #expect(result.contains(where: { $0.build == 48 }))
        #expect(!result.contains(where: { $0.build == 47 }))
    }

    // MARK: - Maximum cap

    // Showing more than 5 entries at once reads like a wall of text. Users who
    // skipped many builds should see the most recent 5 only.
    @Test func atMostFiveEntriesAreReturned() {
        let entries = (1...10).reversed().enumerated().map { idx, build in
            entry(build: build, order: idx)
        }
        let repo = MockChangelogRepository(installedBuild: 10, bundled: entries)
        // lastSeen = 0 means every numbered entry qualifies.
        let seen = MockChangelogSeenStore(lastSeenBuild: 0)
        let useCase = GetWhatsNewUseCase(repository: repo, seenStore: seen)

        let result = useCase.execute()

        #expect(result.count == 5)
    }

    // MARK: - installedBuild == 0

    // Build number 0 is used when the system cannot read the build, e.g. in
    // unit test hosts. The use case must bail out immediately to avoid noise.
    @Test func installedBuildZeroReturnsEmpty() {
        let entries = [entry(build: 49, order: 0)]
        let repo = MockChangelogRepository(installedBuild: 0, bundled: entries)
        let seen = MockChangelogSeenStore(lastSeenBuild: nil)
        let useCase = GetWhatsNewUseCase(repository: repo, seenStore: seen)

        let result = useCase.execute()

        #expect(result.isEmpty)
    }

    // MARK: - Nothing new

    // When the user has already seen the current build (or a newer one), the
    // result is empty and What's New must not be presented.
    @Test func nothingNewWhenLastSeenEqualsInstalledBuild() {
        let entries = [entry(build: 49, order: 0), entry(build: 48, order: 1)]
        let repo = MockChangelogRepository(installedBuild: 49, bundled: entries)
        let seen = MockChangelogSeenStore(lastSeenBuild: 49)
        let useCase = GetWhatsNewUseCase(repository: repo, seenStore: seen)

        let result = useCase.execute()

        #expect(result.isEmpty)
    }

    // Summary sections carry build 0 and must not show up in What's New because
    // they represent historical overviews, not individual release highlights.
    @Test func summaryEntriesWithBuildZeroAreNotShown() {
        let summary = ChangelogEntry(build: 0, version: "1.0", date: nil,
                                     body: "Builds 40-46 summary", title: "Builds 40 to 46", order: 0)
        let current = ChangelogEntry(build: 49, version: "1.0", date: nil, body: "New stuff", order: 1)
        let repo = MockChangelogRepository(installedBuild: 49, bundled: [summary, current])
        let seen = MockChangelogSeenStore(lastSeenBuild: 46)
        let useCase = GetWhatsNewUseCase(repository: repo, seenStore: seen)

        let result = useCase.execute()

        #expect(!result.contains(where: { $0.build == 0 }))
        #expect(result.contains(where: { $0.build == 49 }))
    }
}
