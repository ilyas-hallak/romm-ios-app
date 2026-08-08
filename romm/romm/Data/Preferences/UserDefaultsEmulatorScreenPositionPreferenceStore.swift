import Foundation

final class UserDefaultsEmulatorScreenPositionPreferenceStore: PEmulatorScreenPositionPreference {
    private let key = "emulator.screenPosition"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var position: EmulatorScreenPosition {
        get {
            guard let raw = userDefaults.string(forKey: key),
                  let value = EmulatorScreenPosition(rawValue: raw) else {
                return .center
            }
            return value
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: key)
        }
    }
}
