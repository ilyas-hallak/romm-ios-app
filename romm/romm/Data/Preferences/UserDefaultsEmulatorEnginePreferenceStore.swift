import Foundation

final class UserDefaultsEmulatorEnginePreferenceStore: PEmulatorEnginePreference {
    private let key = "emulator.engine.preference"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        #if !APP_STORE
        persistInitialDefaultIfNeeded()
        #endif
    }

    #if !APP_STORE
    private func persistInitialDefaultIfNeeded() {
        guard userDefaults.object(forKey: key) == nil else { return }
        // These keys predate the Native default. Bootstrap checks them before
        // onboarding or the changelog can create a fresh install's footprint.
        let existingInstallKeys = [
            "setup_configuration_json", "setup_auth_method",
            "lastSeenChangelogBuild", "auth.clientDeviceIdentifier"
        ]
        let isExistingInstall = existingInstallKeys.contains { userDefaults.object(forKey: $0) != nil }
        let engine: EmulatorEngine = isExistingInstall ? .web : .native
        userDefaults.set(engine.rawValue, forKey: key)
    }
    #endif

    var current: EmulatorEngine {
        get {
            // Invalid values retain the on-device fallback. Stored Web choices
            // are coerced when that engine is unavailable in this build.
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
