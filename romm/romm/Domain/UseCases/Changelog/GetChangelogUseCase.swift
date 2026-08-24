import Foundation

protocol PGetChangelogUseCase {
    /// The full bundled version history, newest first.
    func execute() -> [ChangelogEntry]
}

final class GetChangelogUseCase: PGetChangelogUseCase {
    private let repository: PChangelogRepository

    init(repository: PChangelogRepository) {
        self.repository = repository
    }

    func execute() -> [ChangelogEntry] {
        repository.bundledEntries()
    }
}
