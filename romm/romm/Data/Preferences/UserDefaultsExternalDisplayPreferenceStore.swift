import Foundation

final class UserDefaultsExternalDisplayPreferenceStore: PExternalDisplayPreference {
    private let playOnTVKey = "externalDisplay.enabled"
    private let autoDimKey = "externalDisplay.autoDimPhone"
    private let blankedBrightnessKey = "phoneScreenBlanker.savedBrightness"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isPlayOnTVEnabled: Bool {
        get { boolOrTrue(playOnTVKey) }
        set { userDefaults.set(newValue, forKey: playOnTVKey) }
    }

    var isAutoDimPhoneEnabled: Bool {
        get { boolOrTrue(autoDimKey) }
        set { userDefaults.set(newValue, forKey: autoDimKey) }
    }

    var blankedPhoneBrightness: Double? {
        get {
            guard userDefaults.object(forKey: blankedBrightnessKey) != nil else { return nil }
            return userDefaults.double(forKey: blankedBrightnessKey)
        }
        set {
            if let newValue {
                userDefaults.set(newValue, forKey: blankedBrightnessKey)
            } else {
                userDefaults.removeObject(forKey: blankedBrightnessKey)
            }
        }
    }

    /// Both switches default to on, and `UserDefaults.bool` returns false for a
    /// missing key. Once a TV is attached, a portrait phone screen with black bars
    /// is never what the player wanted.
    private func boolOrTrue(_ key: String) -> Bool {
        guard userDefaults.object(forKey: key) != nil else { return true }
        return userDefaults.bool(forKey: key)
    }
}
