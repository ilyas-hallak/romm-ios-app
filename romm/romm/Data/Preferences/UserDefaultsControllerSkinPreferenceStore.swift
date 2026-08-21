import Foundation

/// Persists the per-system skin selection in UserDefaults as a
/// `[gameTypeIdentifier: fileName]` dictionary.
final class UserDefaultsControllerSkinPreferenceStore: PControllerSkinPreference {

    private let key = "emulator.controllerSkin.selection"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func selectedFileName(forGameType gameTypeIdentifier: String) -> String? {
        dictionary[gameTypeIdentifier]
    }

    func setSelectedFileName(_ fileName: String?, forGameType gameTypeIdentifier: String) {
        var dict = dictionary
        dict[gameTypeIdentifier] = fileName
        userDefaults.set(dict, forKey: key)
    }

    // MARK: - Private

    private var dictionary: [String: String] {
        userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
