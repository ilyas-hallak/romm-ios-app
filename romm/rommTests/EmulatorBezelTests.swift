import Foundation
import Testing

@testable import romm

struct EmulatorBezelPreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func defaultIsOff() {
        let pref = UserDefaultsEmulatorBezelPreferenceStore(userDefaults: makeDefaults())
        #expect(pref.isEnabled == false)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let pref1 = UserDefaultsEmulatorBezelPreferenceStore(userDefaults: defaults)
        pref1.isEnabled = true
        let pref2 = UserDefaultsEmulatorBezelPreferenceStore(userDefaults: defaults)
        #expect(pref2.isEnabled)
    }
}

@MainActor
struct EmulatorViewModelBezelTests {
    private final class StubBezelPreference: PEmulatorBezelPreference {
        var isEnabled: Bool

        init(isEnabled: Bool) {
            self.isEnabled = isEnabled
        }
    }

    private func makeRom() -> Rom {
        Rom(id: 1, name: "Test", platformId: 0, urlCover: nil,
            isFavourite: false, hasRetroAchievements: false, isPlayable: true,
            fileName: "Test.nes", platformSlug: "nes")
    }

    private func makeViewModel(bezel: Bool) -> EmulatorViewModel {
        EmulatorViewModel(
            rom: makeRom(),
            bezelPreference: StubBezelPreference(isEnabled: bezel)
        )
    }

    @Test func readsThePreference() {
        #expect(makeViewModel(bezel: true).showsBezel)
        #expect(makeViewModel(bezel: false).showsBezel == false)
    }

    /// The frame must not come and go mid game, so the flag is a snapshot from
    /// the moment the session started.
    @Test func ignoresALaterChange() {
        let preference = StubBezelPreference(isEnabled: false)
        let viewModel = EmulatorViewModel(rom: makeRom(), bezelPreference: preference)

        preference.isEnabled = true

        #expect(viewModel.showsBezel == false)
    }
}
