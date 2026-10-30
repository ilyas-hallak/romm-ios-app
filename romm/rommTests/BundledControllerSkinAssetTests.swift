#if !APP_STORE
import Foundation
import Testing
import UIKit
import DeltaCore
import GBADeltaCore
import GBCDeltaCore
import NESDeltaCore
import SNESDeltaCore
import N64DeltaCore
import GPGXDeltaCore
import MelonDSDeltaCore

struct BundledControllerSkinPointerTests {
    @Test(arguments: ["\n", "\r\n"])
    func canonicalPointerDataIsRecognized(lineEnding: String) {
        #expect(BundledControllerSkinTestSupport.isUnresolvedLFSPointer(data: pointer(lineEnding: lineEnding)))
    }

    @Test(arguments: [
        Data([0x50, 0x4B, 0x05, 0x06] + Array(repeating: 0, count: 18)),
        Data("corrupt archive".utf8),
        Data("version https://git-lfs.github.com/spec/v1\n".utf8),
        Data("version https://git-lfs.github.com/spec/v1\noid sha256:invalid\nsize 123\n".utf8)
    ])
    func archiveOrMalformedDataDoesNotSkipTests(data: Data) {
        #expect(!BundledControllerSkinTestSupport.isUnresolvedLFSPointer(data: data))
    }

    @Test func onlyAnActualPointerFileDisablesTheAssetSuite() throws {
        try withTemporaryAsset { url in
            #expect(BundledControllerSkinTestSupport.shouldRunRealAssetTests(for: [nil, url]))

            try Data("corrupt archive".utf8).write(to: url)
            #expect(BundledControllerSkinTestSupport.shouldRunRealAssetTests(for: [url]))

            try pointer().write(to: url)
            #expect(!BundledControllerSkinTestSupport.shouldRunRealAssetTests(for: [url]))

            // Only a bounded pointer record is allowed to disable the suite.
            try (pointer() + Data(repeating: 0x20, count: 1025)).write(to: url)
            #expect(BundledControllerSkinTestSupport.shouldRunRealAssetTests(for: [url]))
        }
    }

    private func pointer(lineEnding: String = "\n") -> Data {
        Data([
            "version https://git-lfs.github.com/spec/v1",
            "oid sha256:" + String(repeating: "a", count: 64),
            "size 123456", ""
        ].joined(separator: lineEnding).utf8)
    }

    private func withTemporaryAsset(_ test: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledControllerSkinPointerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(directory.appendingPathComponent("Standard.deltaskin"))
    }
}

/// This suite stays enabled so one unresolved pointer cannot hide another
/// core's missing resource, unreadable archive, or broken standard artwork.
@MainActor
struct BundledControllerSkinIntegrityTests {
    @Test(arguments: ["gba", "gbc", "nes", "snes", "n64", "genesis", "ds"])
    func eachBundledSkinIsEitherAnLFSPointerOrAReadableSkin(coreName: String) throws {
        let cores: [String: any DeltaCoreProtocol] = [
            "gba": GBA.core, "gbc": GBC.core, "nes": NES.core,
            "snes": SNES.core, "n64": N64.core, "genesis": GPGX.core,
            "ds": MelonDS.core
        ]
        let core = try #require(cores[coreName])
        let url = try #require(core.resourceBundle.url(forResource: "Standard", withExtension: "deltaskin"))
        if BundledControllerSkinTestSupport.isUnresolvedLFSPointer(at: url) { return }

        let skin = try #require(ControllerSkin(fileURL: url))
        #expect(skin.gameType == core.gameType)
        let traits = ControllerSkin.Traits(device: .iphone, displayType: .standard, orientation: .portrait)
        let image = try #require(skin.image(for: traits, preferredSize: .small))
        #expect(image.cgImage != nil)
    }
}
#endif
