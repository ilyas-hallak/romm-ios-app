import Foundation

final class UserDefaultsEmulatorScreenPositionPreferenceStore: PEmulatorScreenPositionPreference {
    private let modeKey = "emulator.controllerScreenMode"
    private let offsetKey = "emulator.screenVerticalOffset"
    private let heightKey = "emulator.screenHeightFraction"
    /// Legacy key from the first screen-position feature ("center"/"top"). Used
    /// only to migrate existing users to the new mode/offset model.
    private let legacyPositionKey = "emulator.screenPosition"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var mode: ControllerScreenMode {
        get {
            if let raw = userDefaults.string(forKey: modeKey),
               let value = ControllerScreenMode(rawValue: raw) {
                return value
            }
            // Migration: the old "top" position meant "always pin to the top".
            if userDefaults.string(forKey: legacyPositionKey) == "top" { return .always }
            return .off
        }
        set { userDefaults.set(newValue.rawValue, forKey: modeKey) }
    }

    var verticalOffset: Double {
        get {
            if userDefaults.object(forKey: offsetKey) != nil {
                return min(1.0, max(0.0, userDefaults.double(forKey: offsetKey)))
            }
            // Migration: old "top" pinned to the top (offset 0); otherwise center.
            return userDefaults.string(forKey: legacyPositionKey) == "top" ? 0.0 : 0.5
        }
        set { userDefaults.set(min(1.0, max(0.0, newValue)), forKey: offsetKey) }
    }

    var heightFraction: Double {
        get {
            guard userDefaults.object(forKey: heightKey) != nil else { return 1.0 }
            return min(1.0, max(0.3, userDefaults.double(forKey: heightKey)))
        }
        set { userDefaults.set(min(1.0, max(0.3, newValue)), forKey: heightKey) }
    }
}
