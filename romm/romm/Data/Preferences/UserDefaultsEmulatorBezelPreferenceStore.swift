import Foundation

final class UserDefaultsEmulatorBezelPreferenceStore: PEmulatorBezelPreference {
    private let enabledKey = "emulator.bezel.enabled"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: enabledKey) }
        set { userDefaults.set(newValue, forKey: enabledKey) }
    }
}
