import Testing
import Foundation
@testable import romm

struct ExternalEmulatorTests {

    @Test func retroArchLaunchURLUsesTheFileName() {
        let url = ExternalEmulator.retroarch.launchURL(fileName: "Sonic.md")
        #expect(url?.absoluteString == "retroarch://game/Sonic.md")
    }

    /// File names routinely contain spaces, brackets and hashes, all of which
    /// break a URL that is glued together as a string.
    @Test func retroArchLaunchURLEscapesSpecialCharacters() {
        let url = ExternalEmulator.retroarch.launchURL(fileName: "Super Mario 64 (USA) #1.z64")
        #expect(url?.absoluteString == "retroarch://game/Super%20Mario%2064%20(USA)%20%231.z64")
    }

    @Test func launchURLIsNilWithoutAFileName() {
        #expect(ExternalEmulator.retroarch.launchURL(fileName: "") == nil)
    }

    @Test func probeURLIsTheBareScheme() {
        #expect(ExternalEmulator.retroarch.probeURL?.absoluteString == "retroarch://")
    }

    /// RetroArch ships under several bundle identifiers, so the match is on the
    /// substring rather than one fixed id.
    @Test(arguments: [
        "com.libretro.RetroArch",
        "com.libretro.RetroArchiOS11",
        "COM.LIBRETRO.RETROARCH"
    ])
    func recognisesRetroArchBundleIdentifiers(identifier: String) {
        #expect(ExternalEmulator.retroarch.matches(bundleIdentifier: identifier))
    }

    @Test(arguments: ["com.rileytestut.Delta", "com.apple.mobilemail", ""])
    func rejectsOtherBundleIdentifiers(identifier: String) {
        #expect(!ExternalEmulator.retroarch.matches(bundleIdentifier: identifier))
    }
}
