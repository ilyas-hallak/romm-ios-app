import Foundation

final class UserDefaultsEmulatorEnginePreferenceStore: PEmulatorEnginePreference {
    private let key = "emulator.engine.preference"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var current: EmulatorEngine {
        get {
            // Prefer on-device emulation for new and invalid preferences.
            // Native uses DeltaCore first, then libretro for other platforms.
            // The App Store target excludes DeltaCore and uses auto instead.
            // Stored web choices are coerced when that engine is unavailable.
            #if !APP_STORE
            let fallback: EmulatorEngine = .native
            #else
            let fallback: EmulatorEngine = AppFeatures.webEmulatorEnabled ? .web : .auto
            #endif
            guard let raw = userDefaults.string(forKey: key) else { return fallback }
            if let engine = EmulatorEngine(rawValue: raw) {
                #if !APP_STORE
                if engine == .web && !AppFeatures.webEmulatorEnabled { return .native }
                #else
                if engine == .web && !AppFeatures.webEmulatorEnabled { return .auto }
                #endif
                return engine
            }
            #if !APP_STORE
            // Legacy: "deltaCore" used to be the raw value before rename to "native".
            if raw == "deltaCore" { return .native }
            #else
            // Legacy: "deltaCore" used to be the raw value before rename to
            // "native", and "native" itself no longer exists as a case in this
            // build. Coerce both to the on-device fallback.
            if raw == "deltaCore" || raw == "native" { return .auto }
            #endif
            return fallback
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: key)
        }
    }
}
