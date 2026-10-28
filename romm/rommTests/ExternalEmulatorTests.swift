import Testing
import Foundation
@testable import romm

struct RetroArchExternalEmulatorTests {

    private let retroarch = RetroArchExternalEmulator()

    /// Started by path alone, RetroArch takes the first core that claims the
    /// extension, and a DS core claims `gba`. The `topshelf` link names the
    /// core instead (#229).
    @Test func launchURLNamesTheCoreForAKnownSystem() throws {
        let url = try #require(retroarch.launchURL(gameIdentifier: "Game.gba", platformSlug: "gba"))
        #expect(url.absoluteString == "retroarch://topshelf"
                + "?path=~/Documents/RetroArch/downloads/Game.gba"
                + "&core_path=:/Frameworks/mgba.libretro.framework/mgba.libretro")
    }

    /// RetroArch turns `_` into `.` when it packs a core into a framework.
    @Test func coreFrameworkNameFollowsRetroArchsPackaging() throws {
        let url = try #require(retroarch.launchURL(gameIdentifier: "Game.z64", platformSlug: "n64"))
        #expect(queryValue("core_path", in: url)
                == ":/Frameworks/mupen64plus.next.libretro.framework/mupen64plus.next.libretro")
    }

    /// File names routinely contain spaces, brackets, `&` and `+`, which must
    /// come back out of the query unchanged.
    @Test func launchURLKeepsSpecialCharactersInTheFileName() throws {
        let name = "Mario & Luigi + (USA) #1.gba"
        let url = try #require(retroarch.launchURL(gameIdentifier: name, platformSlug: "gba"))
        #expect(queryValue("path", in: url) == "~/Documents/RetroArch/downloads/\(name)")
    }

    /// Disc systems have no built-in engine, and a dozen cores claim `chd` or
    /// `cue`, the Amiga one first.
    @Test(arguments: [
        ("ps", "pcsx.rearmed.libretro"),
        ("psx", "pcsx.rearmed.libretro"),
        ("segacd", "genesis.plus.gx.libretro"),
        ("saturn", "yabause.libretro"),
        ("pc-engine-cd", "mednafen.pce.fast.libretro")
    ])
    func launchURLNamesTheCoreForADiscSystem(platformSlug: String, framework: String) throws {
        let url = try #require(retroarch.launchURL(gameIdentifier: "Game.chd", platformSlug: platformSlug))
        #expect(queryValue("core_path", in: url) == ":/Frameworks/\(framework).framework/\(framework)")
    }

    /// Without a known core RetroArch has to pick one itself, from the file it
    /// finds at the path.
    @Test func launchURLFallsBackToThePathForOtherSystems() {
        let url = retroarch.launchURL(gameIdentifier: "sf2 (World).zip", platformSlug: "arcade")
        #expect(url?.absoluteString == "retroarch://game/~/Documents/RetroArch/downloads/sf2%20(World).zip")
    }

    @Test func launchURLIsNilWithoutAnIdentifier() {
        #expect(retroarch.launchURL(gameIdentifier: "", platformSlug: "gba") == nil)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
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
