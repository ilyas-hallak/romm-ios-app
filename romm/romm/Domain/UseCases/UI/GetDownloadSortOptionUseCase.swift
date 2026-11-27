import Foundation

protocol PGetDownloadSortOptionUseCase {
    func execute() -> DownloadSortOption
}

final class GetDownloadSortOptionUseCase: PGetDownloadSortOptionUseCase {
    private let repository: PDownloadSortPreferenceRepository

    init(repository: PDownloadSortPreferenceRepository) {
        self.repository = repository
    }

    func execute() -> DownloadSortOption {
        repository.get()
    }
}
