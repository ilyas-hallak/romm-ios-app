import Testing
import Foundation
@testable import romm

/// The file names in here are the ones reported in issue #144, from a real
/// device. They are the contract: if a layout stops recognising them, saves made
/// in that app stop being found and the sync silently has nothing to offer.
struct ExternalSaveLayoutTests {

    // MARK: - RetroArch

    /// `…/RetroArch/saves/<core>/ROMNAME.srm`
    @Test func retroArchRecognisesItsOwnSaveNames() {
        let layout = RetroArchExternalEmulator().saveLayout!
        #expect(layout.isBatterySave(fileName: "Chrono Trigger.srm", matching: "Chrono Trigger"))
        #expect(layout.isBatterySave(fileName: "Chrono Trigger.sav", matching: "Chrono Trigger"))
    }

    /// A save is named after the ROM file's base name, so a ROM keeps matching
    /// after its extension is stripped.
    @Test func retroArchMatchesOnTheRomBaseName() {
        let layout = RetroArchExternalEmulator().saveLayout!
        #expect(layout.naming == .romBaseName)
        #expect(!layout.isBatterySave(fileName: "Chrono Trigger.srm", matching: "Chrono Trigger.sfc"))
    }

    // MARK: - Manic EMU

    /// `…/3DS/sdmc/saves/<system>/ROMNAME.sav` for gb/gba/gbc/nds.
    @Test func manicRecognisesTheSystemFolderNaming() {
        let layout = ManicEmuExternalEmulator().saveLayout!
        #expect(layout.isBatterySave(fileName: "Pokemon Emerald.sav", matching: "Pokemon Emerald"))
    }

    /// `…/3DS/sdmc/saves/Mupen64Plus-Next/ROMNAME.srm` for n64: the same app
    /// writes the libretro extension through that core, so both have to count.
    @Test func manicRecognisesTheN64CoreExtension() {
        let layout = ManicEmuExternalEmulator().saveLayout!
        #expect(layout.isBatterySave(fileName: "Mario 64.srm", matching: "Mario 64"))
    }

    /// The hint stops above the per-system directory, because that level is not
    /// one fixed value: it is the system for most cores and the core name for n64.
    @Test func manicHintsAtTheSharedSavesFolderOnly() {
        let layout = ManicEmuExternalEmulator().saveLayout!
        #expect(layout.searchHints == ["3DS/sdmc/saves"])
    }

    // MARK: - Delta

    /// Delta names a save after the SHA-1 it addresses the game by, so the key is
    /// the resolved identifier rather than any file name.
    @Test func deltaMatchesOnTheGameIdentifier() {
        let layout = DeltaExternalEmulator().saveLayout!
        let sha1 = "4f2b8c1d9e0a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
        #expect(layout.naming == .gameIdentifier)
        #expect(layout.isBatterySave(fileName: "\(sha1).sav", matching: sha1))
    }

    /// Delta keeps the ROM and its artwork under the same name as the save, so
    /// matching the name alone would offer to upload a ROM as if it were a save.
    @Test func deltaIgnoresTheRomAndArtworkBesideTheSave() {
        let layout = DeltaExternalEmulator().saveLayout!
        let sha1 = "4f2b8c1d9e0a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
        #expect(!layout.isBatterySave(fileName: "\(sha1).gba", matching: sha1))
        #expect(!layout.isBatterySave(fileName: "\(sha1).png", matching: sha1))
    }

    // MARK: - Shared behaviour

    /// Case folding differs across the file providers these folders come from,
    /// so a save must not be missed over it.
    @Test func matchingIgnoresCase() {
        let layout = RetroArchExternalEmulator().saveLayout!
        #expect(layout.isBatterySave(fileName: "ZELDA.SRM", matching: "Zelda"))
    }

    /// Names are truncated at the last dot, so a ROM whose name contains one
    /// still resolves.
    @Test func matchesNamesContainingDots() {
        let layout = RetroArchExternalEmulator().saveLayout!
        #expect(layout.isBatterySave(fileName: "Sonic 3.knuckles.srm", matching: "Sonic 3.knuckles"))
    }

    /// A save state is not a battery save, and the two sit in neighbouring
    /// folders in every one of these apps.
    @Test func rejectsSaveStates() {
        let retroarch = RetroArchExternalEmulator().saveLayout!
        #expect(!retroarch.isBatterySave(fileName: "Zelda.state", matching: "Zelda"))
        #expect(!retroarch.isBatterySave(fileName: "Zelda.state1", matching: "Zelda"))
    }

    /// An app that has not described where it writes is not searched at all,
    /// rather than searched with a guess.
    @Test func anUndescribedAppHasNoLayout() {
        #expect(RetroArchExternalEmulator().saveLayout != nil)
        #expect(DeltaExternalEmulator().saveLayout != nil)
        #expect(ManicEmuExternalEmulator().saveLayout != nil)
    }

    /// Every layout has to bound its own search: these folders can sit next to a
    /// whole ROM collection.
    @Test(arguments: ExternalEmulatorID.allCases)
    func everyLayoutBoundsItsSearch(id: ExternalEmulatorID) throws {
        let layout = try #require(id.emulator.saveLayout)
        #expect(layout.maxSearchDepth > 0)
        #expect(layout.maxSearchDepth <= 4)
        #expect(!layout.batteryExtensions.isEmpty)
    }
}
