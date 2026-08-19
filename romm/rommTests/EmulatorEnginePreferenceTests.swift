import Testing
import Foundation
@testable import romm

struct EmulatorEnginePreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    /// Expressed against the feature flag rather than hard coded to `.web`: the
    /// store coerces to native in builds where the web engine is unavailable, and
    /// TestFlight and the App Store ship the same binary.
    private var expectedDefault: EmulatorEngine {
        AppFeatures.webEmulatorEnabled ? .web : .native
    }

    @Test func defaultIsTheAvailableEngine() {
        let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: makeDefaults())
        #expect(pref.current == expectedDefault)
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
        #expect(pref.current == expectedDefault)
    }

    /// "deltaCore" was the raw value before the rename to "native".
    @Test func legacyRawValueStillMapsToNative() {
        let defaults = makeDefaults()
        defaults.set("deltaCore", forKey: "emulator.engine.preference")
        let pref = UserDefaultsEmulatorEnginePreferenceStore(userDefaults: defaults)
        #expect(pref.current == .native)
    }
}
