import Foundation

protocol PSaveDownloadSortOptionUseCase {
    func execute(_ option: DownloadSortOption)
}

final class SaveDownloadSortOptionUseCase: PSaveDownloadSortOptionUseCase {
    private let repository: PDownloadSortPreferenceRepository

    init(repository: PDownloadSortPreferenceRepository) {
        self.repository = repository
    }

    func execute(_ option: DownloadSortOption) {
        repository.set(option)
    }
}
