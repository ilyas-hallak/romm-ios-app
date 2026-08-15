import Foundation

final class UserDefaultsEmulatorMenuShortcutPreferenceStore: PEmulatorMenuShortcutPreference {
    private let key = "emulator.menuShortcut.preference"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var current: EmulatorMenuShortcut {
        get {
            guard let raw = userDefaults.string(forKey: key),
                  let shortcut = EmulatorMenuShortcut(rawValue: raw) else { return .none }
            return shortcut
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: key)
        }
    }
}
