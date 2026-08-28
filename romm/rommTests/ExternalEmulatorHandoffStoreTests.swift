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

    /// Hashing a ROM on every Play tap would put seconds between the tap and the
    /// game, so the identifier is worked out once and kept.
    @Test func cachesAContentHashPerRom() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        #expect(store.cachedGameIdentifier(romId: 1, kind: .sha1OfROMData) == nil)

        store.cacheGameIdentifier("abc123", romId: 1, kind: .sha1OfROMData)

        #expect(store.cachedGameIdentifier(romId: 1, kind: .sha1OfROMData) == "abc123")
        #expect(store.cachedGameIdentifier(romId: 2, kind: .sha1OfROMData) == nil)
    }

    /// A file name costs nothing to derive again, and caching it would only add a
    /// way for it to go stale after a re-download.
    @Test func doesNotCacheFileNames() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        store.cacheGameIdentifier("Game.gba", romId: 1, kind: .fileName)
        #expect(store.cachedGameIdentifier(romId: 1, kind: .fileName) == nil)
    }

    /// The same ROM id can point at a different dump after a re-download, so the
    /// hash has to go when the handoff state does.
    @Test func forgetAlsoDropsTheCachedIdentifier() {
        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: makeDefaults())
        store.cacheGameIdentifier("abc123", romId: 1, kind: .sha1OfROMData)
        store.cacheGameIdentifier("def456", romId: 2, kind: .sha1OfROMData)

        store.forget(romId: 1)

        #expect(store.cachedGameIdentifier(romId: 1, kind: .sha1OfROMData) == nil)
        #expect(store.cachedGameIdentifier(romId: 2, kind: .sha1OfROMData) == "def456")
    }

    @Test func cachedIdentifiersPersistAcrossInstances() {
        let defaults = makeDefaults()
        UserDefaultsExternalEmulatorHandoffStore(userDefaults: defaults)
            .cacheGameIdentifier("abc123", romId: 7, kind: .sha1OfROMData)
        let reopened = UserDefaultsExternalEmulatorHandoffStore(userDefaults: defaults)
        #expect(reopened.cachedGameIdentifier(romId: 7, kind: .sha1OfROMData) == "abc123")
    }

    /// The identifier cache went into its own key so that installations from
    /// before it keep the handoffs they already made.
    @Test func readsHandoffStateWrittenBeforeTheIdentifierCacheExisted() {
        let defaults = makeDefaults()
        defaults.set([4, 5], forKey: "externalEmulator.handoff.retroarch")

        let store = UserDefaultsExternalEmulatorHandoffStore(userDefaults: defaults)

        #expect(store.hasHandedOff(romId: 4, to: .retroarch))
        #expect(store.hasHandedOff(romId: 5, to: .retroarch))
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
