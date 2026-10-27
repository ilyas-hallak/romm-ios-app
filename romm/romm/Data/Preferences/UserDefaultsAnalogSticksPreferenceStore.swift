import Foundation

final class UserDefaultsAnalogSticksPreferenceStore: PAnalogSticksPreference {
    private let key = "emulator.playstation.analogSticks"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: key) }
        set { userDefaults.set(newValue, forKey: key) }
    }
}
