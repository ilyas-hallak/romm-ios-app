import Foundation

protocol PDownloadSortPreferenceRepository {
    func get() -> DownloadSortOption
    func set(_ option: DownloadSortOption)
}
