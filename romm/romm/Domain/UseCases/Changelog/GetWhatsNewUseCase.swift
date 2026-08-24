import Foundation

protocol PGetWhatsNewUseCase {
    /// Entries the user has not been shown yet, newest first. Empty when there is
    /// nothing new, which is also the signal not to present What's New at all.
    func execute() -> [ChangelogEntry]
}

final class GetWhatsNewUseCase: PGetWhatsNewUseCase {
    /// More than a handful of build notes at once reads like a wall of text, so
    /// a user who skipped several updates only sees the most recent ones.
    private static let maximumEntries = 5

    private let repository: PChangelogRepository
    private let seenStore: PChangelogSeenStore

    init(repository: PChangelogRepository, seenStore: PChangelogSeenStore) {
        self.repository = repository
        self.seenStore = seenStore
    }

    func execute() -> [ChangelogEntry] {
        let installedBuild = repository.installedBuild
        guard installedBuild > 0 else { return [] }

        let entries = repository.bundledEntries()

        guard let lastSeen = seenStore.lastSeenBuild else {
            // Fresh install: the full history would be noise, so show only what
            // this build brought.
            return entries.filter { $0.build == installedBuild }
        }

        return Array(entries.filter { $0.build > lastSeen }.prefix(Self.maximumEntries))
    }
}
