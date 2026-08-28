import Foundation

/// Persists the Play destination as a plain string: `"builtIn"` or the raw value
/// of an `ExternalEmulatorID`.
final class UserDefaultsPlayTargetPreferenceStore: PPlayTargetPreference {

    private let key = "emulator.playTarget"
    private let builtInValue = "builtIn"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var current: PlayTarget {
        get {
            guard let raw = userDefaults.string(forKey: key), raw != builtInValue else { return .builtIn }
            // An emulator that was removed from the app in a later version falls
            // back to the built-in one rather than leaving Play without a target.
            guard let id = ExternalEmulatorID(rawValue: raw) else { return .builtIn }
            return .external(id)
        }
        set {
            switch newValue {
            case .builtIn:
                userDefaults.set(builtInValue, forKey: key)
            case .external(let id):
                userDefaults.set(id.rawValue, forKey: key)
            }
        }
    }
}
