import Foundation

protocol PMarkChangelogSeenUseCase {
    func execute()
}

final class MarkChangelogSeenUseCase: PMarkChangelogSeenUseCase {
    private let repository: PChangelogRepository
    private let seenStore: PChangelogSeenStore

    init(repository: PChangelogRepository, seenStore: PChangelogSeenStore) {
        self.repository = repository
        self.seenStore = seenStore
    }

    func execute() {
        let installedBuild = repository.installedBuild
        guard installedBuild > 0 else { return }
        seenStore.lastSeenBuild = installedBuild
    }
}
