import Testing
import Foundation
@testable import romm

struct ManicEmuExternalEmulatorTests {

    private let manic = ManicEmuExternalEmulator()

    /// Manic only treats a host as special when it belongs to one of the emulators
    /// it hands games off to itself (`xenios`, `dukex`, `armsx2`, `atariemulator`).
    /// `game` is not one of those, so the link falls through to the branch that
    /// reads the last path component as a game id.
    @Test func launchURLUsesTheSharedGameHost() {
        let id = "8957039215404510875"
        #expect(manic.launchURL(gameIdentifier: id)?.absoluteString == "manicemu://game/\(id)")
    }

    /// A host Manic reserves for one of its own handoff targets would be parsed as
    /// that instead of as a game, so the identifier must never end up there.
    @Test(arguments: ["xenios", "dukex", "armsx2", "atariemulator"])
    func launchURLDoesNotCollideWithManicsReservedHosts(reserved: String) {
        let url = manic.launchURL(gameIdentifier: "123")
        #expect(url?.host == "game")
        #expect(url?.host != reserved)
    }

    @Test func launchURLIsNilWithoutAnIdentifier() {
        #expect(manic.launchURL(gameIdentifier: "") == nil)
    }

    @Test func probeURLIsTheBareScheme() {
        #expect(manic.probeURL?.absoluteString == "manicemu://")
    }

    /// Manic unpacks archives and hashes what came out, so it has to be handed the
    /// plain ROM for its id and ours to agree.
    @Test func wantsTheUnpackedROM() {
        #expect(manic.wantsUnpackedROM)
        #expect(manic.identifierKind == .manicGameID)
    }

    /// Manic drops a file the "Open in" menu put in its inbox, because taking a
    /// security scope on it fails. Only the pasteboard route reaches its importer.
    @Test func takesTheROMOffThePasteboard() {
        #expect(manic.romDelivery == .pasteboard)
    }

    /// The App Store build, plus StikStore and SideStore sideloads that re-sign
    /// under a different team.
    @Test(arguments: [
        "com.aoshuang.manicemu",
        "com.aoshuang.ManicEmu",
        "com.aoshuang.manicemu.A1B2C3D4E5"
    ])
    func recognisesManicBundleIdentifiers(identifier: String) {
        #expect(manic.matches(bundleIdentifier: identifier))
    }

    @Test(arguments: ["com.rileytestut.Delta", "com.libretro.RetroArch", "", "com.aoshuang.other"])
    func rejectsOtherBundleIdentifiers(identifier: String) {
        #expect(!manic.matches(bundleIdentifier: identifier))
    }

    /// Archives have to stay out: the resolver would hand the archive over and
    /// hash that, while Manic unpacks it first and hashes the result, so the deep
    /// link would never resolve.
    @Test(arguments: ["zip", "7z", "rar"])
    func declaresNoArchiveExtensions(archive: String) {
        #expect(manic.romExtensions?.contains(archive) == false)
    }

    /// Multi-file disc formats need a sheet plus separate tracks, which a single
    /// hashed file cannot stand in for. `bin` is also ambiguous and would match a
    /// data track.
    @Test(arguments: ["cue", "iso", "bin", "m3u", "gdi"])
    func declaresNoMultiFileDiscExtensions(disc: String) {
        #expect(manic.romExtensions?.contains(disc) == false)
    }

    /// Unlike `cue`/`bin`, a whole PS1 disc fits in one `chd` or `pbp` file, so
    /// hashing it is no different from any other single ROM file. RomM serves
    /// the vast majority of its PS1 library this way.
    @Test(arguments: ["chd", "pbp"])
    func declaresSingleFileDiscExtensions(disc: String) {
        #expect(manic.romExtensions?.contains(disc) == true)
    }

    /// Platforms a built-in engine already plays go through their game type, whose
    /// extension set is narrower, so listing them here too would only add a way to
    /// pick the wrong file.
    @Test(arguments: ["gba", "gbc", "gb", "nes", "snes", "sfc", "smc", "nds", "n64", "z64", "md"])
    func leavesBuiltInPlatformsToTheirGameType(builtIn: String) {
        #expect(manic.romExtensions?.contains(builtIn) == false)
    }

    /// The point of the list: systems no built-in engine plays.
    @Test(arguments: ["3ds", "cia", "vb", "min", "32x", "gg", "sms", "a26", "j64", "lnx", "pce", "ngp", "wad", "jar"])
    func coversPlatformsOnlyManicPlays(extra: String) {
        #expect(manic.romExtensions?.contains(extra) == true)
    }

    /// The system's generic type for both extensions resolves to one of Manic's
    /// own UTIs whose candidate list has no PS1 entry, so the pasteboard item has
    /// to carry a Manic type that does list it, or the platform picker Manic
    /// shows on paste leaves PS1 out.
    @Test func overridesThePasteboardTypeForSingleFileDiscImages() {
        #expect(manic.pasteboardTypeIdentifier(forROMExtension: "chd") == "public.aoshuang.game.mcd")
        #expect(manic.pasteboardTypeIdentifier(forROMExtension: "pbp") == "public.aoshuang.game.ps1")
    }

    @Test(arguments: ["gba", "nds", "zip", "cue", "wad"])
    func leavesOtherExtensionsToTheSystemsOwnTypeGuess(other: String) {
        #expect(manic.pasteboardTypeIdentifier(forROMExtension: other) == nil)
    }
}
