import Testing
import Foundation
@testable import romm

struct EmulatorEnginePreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func freshInstallDefaultsToNativeDeltaCores() {
        let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: makeDefaults())
        #expect(pref.current == .native)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let pref1 = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
        pref1.current = .native
        let pref2 = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
        #expect(pref2.current == .native)
    }

    @Test func unknownRawValueFallsBack() {
        let defaults = makeDefaults()
        defaults.set("xxx", forKey: "emulator.engine.preference")
        let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
        #expect(pref.current == .native)
    }

    /// "deltaCore" was the raw value before the rename to "native".
    @Test func legacyRawValueStillMapsToNative() {
        let defaults = makeDefaults()
        defaults.set("deltaCore", forKey: "emulator.engine.preference")
        let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
        #expect(pref.current == .native)
    }
}
