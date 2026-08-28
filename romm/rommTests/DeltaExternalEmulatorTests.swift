import Testing
import Foundation
@testable import romm

struct DeltaExternalEmulatorTests {

    private let delta = DeltaExternalEmulator()

    /// Delta parses the identifier as the URL's last path component and looks it
    /// up as `Game.identifier`, which is the ROM's SHA-1.
    @Test func launchURLUsesTheSHA1() {
        let sha1 = "a9993e364706816aba3e25717850c26c9cd0d89d"
        #expect(delta.launchURL(gameIdentifier: sha1)?.absoluteString == "delta://game/\(sha1)")
    }

    @Test func launchURLIsNilWithoutAnIdentifier() {
        #expect(delta.launchURL(gameIdentifier: "") == nil)
    }

    @Test func probeURLIsTheBareScheme() {
        #expect(delta.probeURL?.absoluteString == "delta://")
    }

    /// Delta hashes the ROM it ends up with, so it has to be handed the plain ROM
    /// rather than the archive it is stored in.
    @Test func wantsTheUnpackedROM() {
        #expect(delta.wantsUnpackedROM)
        #expect(delta.identifierKind == .sha1OfROMData)
    }

    /// The App Store build, plus sideloads that get a team id appended.
    @Test(arguments: [
        "com.rileytestut.Delta",
        "com.rileytestut.delta",
        "com.rileytestut.Delta.A1B2C3D4E5"
    ])
    func recognisesDeltaBundleIdentifiers(identifier: String) {
        #expect(delta.matches(bundleIdentifier: identifier))
    }

    @Test(arguments: ["com.libretro.RetroArch", "com.rileytestut.Clip", "", "org.provenance.Provenance"])
    func rejectsOtherBundleIdentifiers(identifier: String) {
        #expect(!delta.matches(bundleIdentifier: identifier))
    }
}
