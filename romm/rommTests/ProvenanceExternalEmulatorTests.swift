import Testing
import Foundation
@testable import romm

struct ProvenanceExternalEmulatorTests {

    private let provenance = ProvenanceExternalEmulator()

    /// Provenance reads the identifier out of an `md5` query parameter and looks
    /// it up against the MD5 it stored on import. The shared `<scheme>://game/<id>`
    /// form resolves to nothing here, so this is the one deep link that has to be
    /// built differently from the others.
    @Test func launchURLPutsTheMD5InTheQuery() {
        let md5 = "900150983cd24fb0d6963f7d28e17f72"
        #expect(provenance.launchURL(gameIdentifier: md5)?.absoluteString
                == "provenance://open?md5=\(md5)")
    }

    @Test func launchURLIsNilWithoutAnIdentifier() {
        #expect(provenance.launchURL(gameIdentifier: "") == nil)
    }

    @Test func probeURLIsTheBareScheme() {
        #expect(provenance.probeURL?.absoluteString == "provenance://")
    }

    /// Provenance hashes the ROM it ends up with, so it has to be handed the
    /// plain ROM rather than the archive it is stored in.
    @Test func wantsTheUnpackedROM() {
        #expect(provenance.wantsUnpackedROM)
        #expect(provenance.identifierKind == .md5OfROMData)
    }

    /// The share sheet drops the ROM into `Documents/Imports`, where Provenance
    /// watches for it. That is also the only route that reports the handoff back,
    /// so it must stay on the default.
    @Test func takesTheROMFromTheOpenInMenu() {
        #expect(provenance.romDelivery == .openInMenu)
    }

    /// Nothing tells the user the import finished and Provenance does not start
    /// the game, so the assistant has to say that the first game is started by
    /// hand. Without it the share sheet looks like it did nothing.
    @Test func handoffSaysTheFirstGameHasToBeStartedByHand() {
        let text = provenance.handoffExplanation
        #expect(text.localizedCaseInsensitiveContains("share sheet"))
        #expect(text.localizedCaseInsensitiveContains("library"))
        #expect(!text.localizedCaseInsensitiveContains("paste"))
    }

    /// The App Store build, plus nightly and sideloaded builds that append to
    /// the bundle id.
    @Test(arguments: [
        "org.provenance-emu.provenance",
        "org.provenance-emu.Provenance",
        "org.provenance-emu.provenance-nightly",
        "org.provenance-emu.provenance.A1B2C3D4E5"
    ])
    func recognisesProvenanceBundleIdentifiers(identifier: String) {
        #expect(provenance.matches(bundleIdentifier: identifier))
    }

    @Test(arguments: ["com.libretro.RetroArch", "com.rileytestut.Delta", "", "org.provenance.Provenance"])
    func rejectsOtherBundleIdentifiers(identifier: String) {
        #expect(!provenance.matches(bundleIdentifier: identifier))
    }
}
