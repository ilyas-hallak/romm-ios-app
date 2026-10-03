//
//  RomFileExtensionPlatformHintTests.swift
//  rommTests
//

import Testing
@testable import romm

struct RomFileExtensionPlatformHintTests {

    @Test func aGameBoyAdvanceFileSuggestsOnlyItsOwnSlug() {
        #expect(RomFileExtensionPlatformHint.candidateSlugs(forFileName: "Pokemon.gba") == ["gba"])
    }

    @Test func theExtensionIsMatchedCaseInsensitively() {
        #expect(RomFileExtensionPlatformHint.candidateSlugs(forFileName: "Pokemon.GBA") == ["gba"])
    }

    @Test func aGenesisFileOffersEverySlugVariantTheServerMightUse() {
        #expect(
            RomFileExtensionPlatformHint.candidateSlugs(forFileName: "Sonic.md") ==
            ["genesis-slash-megadrive", "genesis", "megadrive"]
        )
    }

    @Test func anUnknownExtensionHasNoCandidates() {
        #expect(RomFileExtensionPlatformHint.candidateSlugs(forFileName: "archive.zip").isEmpty)
    }

    @Test func aFileWithoutAnExtensionHasNoCandidates() {
        #expect(RomFileExtensionPlatformHint.candidateSlugs(forFileName: "noextension").isEmpty)
    }

    @Test func snesSharesItsSlugAcrossBothCommonExtensions() {
        #expect(RomFileExtensionPlatformHint.candidateSlugs(forFileName: "game.sfc") == ["snes"])
        #expect(RomFileExtensionPlatformHint.candidateSlugs(forFileName: "game.smc") == ["snes"])
    }
}
