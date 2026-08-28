import Foundation

final class UserDefaultsRumblePreferenceStore: PRumblePreference {
    private let enabledKey = "emulator.rumble.enabled"
    private let intensityKey = "emulator.rumble.intensity"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isEnabled: Bool {
        get { userDefaults.bool(forKey: enabledKey) }
        set { userDefaults.set(newValue, forKey: enabledKey) }
    }

    var intensity: RumbleIntensity {
        get {
            guard let raw = userDefaults.string(forKey: intensityKey),
                  let intensity = RumbleIntensity(rawValue: raw) else { return .medium }
            return intensity
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: intensityKey)
        }
    }
}
