import Foundation

final class UserDefaultsEmulatorEnginePreferenceStore: PEmulatorEnginePreference {
    private let key = "emulator.engine.preference"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var current: EmulatorEngine {
        get {
            // When the web engine is disabled (distributed builds), native is the
            // only usable default and any previously stored `.web` is coerced.
            let fallback: EmulatorEngine = AppFeatures.webEmulatorEnabled ? .web : .native
            guard let raw = userDefaults.string(forKey: key) else { return fallback }
            if let engine = EmulatorEngine(rawValue: raw) {
                if engine == .web && !AppFeatures.webEmulatorEnabled { return .native }
                return engine
            }
            // Legacy: "deltaCore" used to be the raw value before rename to "native".
            if raw == "deltaCore" { return .native }
            return fallback
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: key)
        }
    }
}
