import Testing
import Foundation
@testable import romm

struct RetroArchExternalEmulatorTests {

    private let retroarch = RetroArchExternalEmulator()

    /// A bare file name only resolves against RetroArch's playlists, and the App
    /// Store build has no content database to put an import there. A path
    /// starting with `~` is resolved against its home directory instead, where
    /// the import always lands (#229).
    @Test func launchURLPointsAtTheImportedFile() {
        let url = retroarch.launchURL(gameIdentifier: "Sonic.md")
        #expect(url?.absoluteString == "retroarch://game/~/Documents/RetroArch/downloads/Sonic.md")
    }

    /// File names routinely contain spaces, brackets and hashes, all of which
    /// break a URL that is glued together as a string.
    @Test func launchURLEscapesSpecialCharacters() {
        let url = retroarch.launchURL(gameIdentifier: "Super Mario 64 (USA) #1.z64")
        #expect(url?.absoluteString
                == "retroarch://game/~/Documents/RetroArch/downloads/Super%20Mario%2064%20(USA)%20%231.z64")
        #expect(url?.path == "/~/Documents/RetroArch/downloads/Super Mario 64 (USA) #1.z64")
    }

    @Test func launchURLIsNilWithoutAnIdentifier() {
        #expect(retroarch.launchURL(gameIdentifier: "") == nil)
    }

    @Test func probeURLIsTheBareScheme() {
        #expect(retroarch.probeURL?.absoluteString == "retroarch://")
    }

    /// The unpacked ROM's extension is what makes RetroArch pick a matching
    /// core when it starts the file by path.
    @Test func wantsTheUnpackedROM() {
        #expect(retroarch.wantsUnpackedROM)
        #expect(retroarch.identifierKind == .fileName)
    }

    /// RetroArch imports what the "Open in" menu hands it, which is also the only
    /// route that reports the handoff back, so it must stay on the default.
    @Test func takesTheROMFromTheOpenInMenu() {
        #expect(retroarch.romDelivery == .openInMenu)
    }

    /// RetroArch ships under several bundle identifiers, so the match is on the
    /// substring rather than one fixed id.
    @Test(arguments: [
        "com.libretro.RetroArch",
        "com.libretro.RetroArchiOS11",
        "COM.LIBRETRO.RETROARCH"
    ])
    func recognisesRetroArchBundleIdentifiers(identifier: String) {
        #expect(retroarch.matches(bundleIdentifier: identifier))
    }

    @Test(arguments: ["com.rileytestut.Delta", "com.apple.mobilemail", ""])
    func rejectsOtherBundleIdentifiers(identifier: String) {
        #expect(!retroarch.matches(bundleIdentifier: identifier))
    }
}

struct ExternalEmulatorIDTests {

    /// The raw values are persistence keys. Renaming a case would silently reset
    /// every user's Play target and lose their handoff state.
    @Test func rawValuesAreTheStoredPreferenceValues() {
        #expect(ExternalEmulatorID.retroarch.rawValue == "retroarch")
        #expect(ExternalEmulatorID.delta.rawValue == "delta")
        // Spelled out because the case name and the key differ here, and the
        // default synthesised value would be "manicEmu".
        #expect(ExternalEmulatorID.manicEmu.rawValue == "manicemu")
        #expect(ExternalEmulatorID.provenance.rawValue == "provenance")
    }

    /// Catches a `switch` branch wired to the wrong implementation.
    @Test func everyCaseResolvesToItsOwnEmulator() {
        for id in ExternalEmulatorID.allCases {
            #expect(id.emulator.id == id)
        }
    }

    @Test func everyEmulatorHasADistinctScheme() {
        let schemes = ExternalEmulatorID.allCases.map { $0.emulator.urlScheme }
        #expect(Set(schemes).count == schemes.count)
    }

    /// Only Manic overrides the pasteboard type for `chd`/`pbp`. Every other app
    /// has to fall through to the default, so the system's own type guess decides.
    @Test func onlyManicOverridesThePasteboardType() {
        for id in ExternalEmulatorID.allCases where id != .manicEmu {
            #expect(id.emulator.pasteboardTypeIdentifier(forROMExtension: "chd", platformSlug: "ps") == nil)
            #expect(id.emulator.pasteboardTypeIdentifier(forROMExtension: "pbp", platformSlug: "ps") == nil)
        }
    }
}
