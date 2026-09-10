import Foundation

final class UserDefaultsEmulatorEnginePreferenceStore: PEmulatorEnginePreference {
    private let key = "emulator.engine.preference"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var current: EmulatorEngine {
        get {
            // When the web engine is disabled (distributed builds), the on-device
            // engine is the only usable default and any previously stored `.web`
            // is coerced. That is `.native` (DeltaCore, falling back to libretro
            // per platform) when built with DELTA_CORES, and `.auto` otherwise,
            // since libretro is then the only on-device engine there is.
            #if DELTA_CORES
            let fallback: EmulatorEngine = AppFeatures.webEmulatorEnabled ? .web : .native
            #else
            let fallback: EmulatorEngine = AppFeatures.webEmulatorEnabled ? .web : .auto
            #endif
            guard let raw = userDefaults.string(forKey: key) else { return fallback }
            if let engine = EmulatorEngine(rawValue: raw) {
                #if DELTA_CORES
                if engine == .web && !AppFeatures.webEmulatorEnabled { return .native }
                #else
                if engine == .web && !AppFeatures.webEmulatorEnabled { return .auto }
                #endif
                return engine
            }
            #if DELTA_CORES
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
