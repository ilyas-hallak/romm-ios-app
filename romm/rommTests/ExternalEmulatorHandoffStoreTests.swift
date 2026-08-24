import Testing
import Foundation
@testable import romm

struct ExternalEmulatorHandoffStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func nothingIsHandedOffInitially() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        #expect(!store.hasHandedOff(romId: 1, to: .retroarch))
    }

    @Test func remembersAHandoffPerRom() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        store.markHandedOff(romId: 1, to: .retroarch)
        #expect(store.hasHandedOff(romId: 1, to: .retroarch))
        #expect(!store.hasHandedOff(romId: 2, to: .retroarch))
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        UserDefaultsExternalEmulatorHandoffStore(userDefaults: defaults)
            .markHandedOff(romId: 7, to: .retroarch)
        let reopened = UserDefaultsExternalEmulatorHandoffStore(userDefaults: defaults)
        #expect(reopened.hasHandedOff(romId: 7, to: .retroarch))
    }

    @Test func markingTwiceKeepsASingleEntry() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        store.markHandedOff(romId: 3, to: .retroarch)
        store.markHandedOff(romId: 3, to: .retroarch)
        #expect(store.hasHandedOff(romId: 3, to: .retroarch))
    }

    /// Called when a deep link is refused or the ROM is deleted, so the next Play
    /// hands the file over again instead of dead-ending.
    @Test func forgetDropsTheRomFromEveryTarget() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        store.markHandedOff(romId: 4, to: .retroarch)
        store.markHandedOff(romId: 5, to: .retroarch)

        store.forget(romId: 4)

        #expect(!store.hasHandedOff(romId: 4, to: .retroarch))
        #expect(store.hasHandedOff(romId: 5, to: .retroarch))
    }

    @Test func forgettingAnUnknownRomIsHarmless() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        store.markHandedOff(romId: 1, to: .retroarch)
        store.forget(romId: 99)
        #expect(store.hasHandedOff(romId: 1, to: .retroarch))
    }
}

struct PlayTargetPreferenceTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func defaultsToTheBuiltInEmulator() {
        let preference = UserDefaultsPlayTargetPreferenceStore(userDefaults: makeDefaults())
        #expect(preference.current == .builtIn)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let preference = UserDefaultsPlayTargetPreferenceStore(userDefaults: defaults)
        preference.current = .external(.retroarch)
        let reopened = UserDefaultsPlayTargetPreferenceStore(userDefaults: defaults)
        #expect(reopened.current == .external(.retroarch))
    }

    @Test func switchingBackToBuiltInSticks() {
        let defaults = makeDefaults()
        let preference = UserDefaultsPlayTargetPreferenceStore(userDefaults: defaults)
        preference.current = .external(.retroarch)
        preference.current = .builtIn
        #expect(UserDefaultsPlayTargetPreferenceStore(userDefaults: defaults).current == .builtIn)
    }

    /// An emulator dropped in a later app version must not leave Play pointing at
    /// something that no longer exists.
    @Test func unknownEmulatorFallsBackToBuiltIn() {
        let defaults = makeDefaults()
        defaults.set("someRetiredEmulator", forKey: "emulator.playTarget")
        let preference = UserDefaultsPlayTargetPreferenceStore(userDefaults: defaults)
        #expect(preference.current == .builtIn)
    }
}
