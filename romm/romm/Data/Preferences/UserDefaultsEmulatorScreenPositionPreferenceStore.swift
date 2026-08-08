import Foundation

final class UserDefaultsEmulatorScreenPositionPreferenceStore: PEmulatorScreenPositionPreference {
    private let key = "emulator.screenPosition"
    private let heightKey = "emulator.screenHeightFraction"
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

    var heightFraction: Double {
        get {
            guard userDefaults.object(forKey: heightKey) != nil else { return 1.0 }
            return userDefaults.double(forKey: heightKey)
        }
        set {
            userDefaults.set(min(1.0, max(0.3, newValue)), forKey: heightKey)
        }
    }
}
