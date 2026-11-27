import Foundation

final class UserDefaultsDownloadSortPreferenceStore: PDownloadSortPreferenceRepository {
    private let key = "selectedDownloadSortOption"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func get() -> DownloadSortOption {
        if let raw = userDefaults.string(forKey: key), let option = DownloadSortOption(rawValue: raw) {
            return option
        }
        return .downloadDate
    }

    func set(_ option: DownloadSortOption) {
        userDefaults.set(option.rawValue, forKey: key)
    }
}
