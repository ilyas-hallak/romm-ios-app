import Testing
import Foundation
@testable import romm

struct EmulatorEnginePreferenceTests {
    private let engineKey = "emulator.engine.preference"

    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        test(defaults)
    }

    @Test func freshInstallDefaultsToNativeDeltaCores() {
        withDefaults { defaults in
            let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            #expect(pref.current == .native)
            #expect(defaults.string(forKey: engineKey) == EmulatorEngine.native.rawValue)
        }
    }

    @Test(arguments: [
        "setup_configuration_json", "setup_auth_method",
        "lastSeenChangelogBuild", "auth.clientDeviceIdentifier"
    ])
    func upgradedInstallWithoutEnginePreservesItsWebDefault(footprintKey: String) {
        withDefaults { defaults in
            switch footprintKey {
            case "setup_configuration_json":
                defaults.set("{\"serverURL\":\"https://example.invalid\"}", forKey: footprintKey)
            case "setup_auth_method":
                defaults.set(AuthMethod.clientToken.rawValue, forKey: footprintKey)
            case "lastSeenChangelogBuild":
                defaults.set(42, forKey: footprintKey)
            default:
                defaults.set(UUID().uuidString, forKey: footprintKey)
            }

            let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            #expect(defaults.string(forKey: engineKey) == EmulatorEngine.web.rawValue)
            #expect(pref.current == (AppFeatures.webEmulatorEnabled ? .web : .native))
        }
    }

    @Test func freshDefaultIsResolvedBeforeOnboardingAndRetainedAcrossLaunches() {
        withDefaults { defaults in
            _ = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            defaults.set(42, forKey: "lastSeenChangelogBuild")
            defaults.set("{}", forKey: "setup_configuration_json")

            let nextLaunch = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            #expect(nextLaunch.current == .native)
            #expect(defaults.string(forKey: engineKey) == EmulatorEngine.native.rawValue)
        }
    }

    @Test func migratedDefaultIsNotReconsideredAfterSetupIsCleared() {
        withDefaults { defaults in
            defaults.set(42, forKey: "lastSeenChangelogBuild")
            _ = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            defaults.removeObject(forKey: "lastSeenChangelogBuild")

            let nextLaunch = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            #expect(nextLaunch.current == (AppFeatures.webEmulatorEnabled ? .web : .native))
            #expect(defaults.string(forKey: engineKey) == EmulatorEngine.web.rawValue)
        }
    }

    @Test(arguments: [EmulatorEngine.native, .web, .auto])
    func explicitChoiceSurvivesUpgradeAndReinitialization(engine: EmulatorEngine) {
        withDefaults { defaults in
            defaults.set(42, forKey: "lastSeenChangelogBuild")
            defaults.set(engine.rawValue, forKey: engineKey)
            _ = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            let nextLaunch = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)

            let expected: EmulatorEngine = engine == .web && !AppFeatures.webEmulatorEnabled ? .native : engine
            #expect(nextLaunch.current == expected)
            #expect(defaults.string(forKey: engineKey) == engine.rawValue)
        }
    }

    @Test func changingTheMigratedPreferenceRemainsPersisted() {
        withDefaults { defaults in
            defaults.set(42, forKey: "lastSeenChangelogBuild")
            let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            pref.current = .native

            let nextLaunch = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            #expect(nextLaunch.current == .native)
            #expect(defaults.string(forKey: engineKey) == EmulatorEngine.native.rawValue)
        }
    }

    @Test(arguments: ["", "xxx", "future-engine"])
    func unknownRawValueKeepsItsFallbackWithoutRunningTheMissingKeyMigration(raw: String) {
        withDefaults { defaults in
            defaults.set(42, forKey: "lastSeenChangelogBuild")
            defaults.set(raw, forKey: engineKey)
            let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            #expect(pref.current == .native)
            #expect(defaults.string(forKey: engineKey) == raw)
        }
    }

    /// "deltaCore" was the raw value before the rename to "native".
    @Test func legacyRawValueStillMapsToNative() {
        withDefaults { defaults in
            defaults.set(42, forKey: "lastSeenChangelogBuild")
            defaults.set("deltaCore", forKey: engineKey)
            let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
            #expect(pref.current == .native)
            #expect(defaults.string(forKey: engineKey) == "deltaCore")
        }
    }
}
