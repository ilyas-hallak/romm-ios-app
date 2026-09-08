import Testing
import Foundation
@testable import romm

/// Hands out a folder in the temporary directory. Nothing here is security
/// scoped, which is the one part of the real thing a test cannot stand in for.
private final class FakeFolderStore: PExternalSaveFolderStore, @unchecked Sendable {
    var folders: [ExternalEmulatorID: URL] = [:]
    var stale: Set<ExternalEmulatorID> = []

    func remember(folderURL: URL, for emulator: ExternalEmulatorID) throws {
        folders[emulator] = folderURL
    }

    func grantedFolder(for emulator: ExternalEmulatorID) -> ExternalSaveFolderGrant? {
        guard let url = folders[emulator] else { return nil }
        return ExternalSaveFolderGrant(url: url, isStale: stale.contains(emulator), scoped: false)
    }

    func forget(_ emulator: ExternalEmulatorID) { folders[emulator] = nil }
    func grantedEmulators() -> [ExternalEmulatorID] { Array(folders.keys) }
}

private final class FakeLocalROMs: PLocalROMRepository, @unchecked Sendable {
    var roms: [DownloadedROM] = []

    var romsBaseURL: URL { FileManager.default.temporaryDirectory }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { roms }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { roms.first { $0.id == id } }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { roms.count }
}

private final class FakeHandoffStore: PExternalEmulatorHandoffStore, @unchecked Sendable {
    var identifiers: [Int: String] = [:]

    func hasHandedOff(romId: Int, to target: ExternalEmulatorID) -> Bool { false }
    func markHandedOff(romId: Int, to target: ExternalEmulatorID) {}
    func forget(romId: Int) {}
    func cachedGameIdentifier(romId: Int, kind: ExternalGameIdentifierKind) -> String? {
        identifiers[romId]
    }
    func cacheGameIdentifier(_ identifier: String, romId: Int, kind: ExternalGameIdentifierKind) {}
}

struct ScanExternalSavesUseCaseTests {

    private func makeRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanExternalSaves-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ path: String, in root: URL, bytes: Int = 32) {
        let url = root.appendingPathComponent(path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? Data(repeating: 0xAB, count: bytes).write(to: url)
    }

    private func rom(id: Int, fileName: String) -> DownloadedROM {
        DownloadedROM(
            id: id, name: fileName, platformName: "GBA", platformSlug: "gba",
            downloadedAt: Date(), totalSizeBytes: 1024, localDirectory: "gba/\(id)",
            files: [DownloadedROMFile(fileName: fileName, fileSizeBytes: 1024)],
            urlCover: nil
        )
    }

    private func makeUseCase(
        root: URL,
        emulator: ExternalEmulatorID,
        roms: [DownloadedROM],
        identifiers: [Int: String] = [:]
    ) -> (ScanExternalSavesUseCase, FakeFolderStore) {
        let folders = FakeFolderStore()
        folders.folders[emulator] = root
        let localROMs = FakeLocalROMs()
        localROMs.roms = roms
        let handoff = FakeHandoffStore()
        handoff.identifiers = identifiers
        return (
            ScanExternalSavesUseCase(folderStore: folders, localROMs: localROMs, handoffStore: handoff),
            folders
        )
    }

    // MARK: - Finding saves where the apps actually put them

    /// The RetroArch path from issue #144, core directory and all.
    @Test func findsRetroArchSavesUnderTheCoreFolder() throws {
        let root = makeRoot()
        write("RetroArch/saves/mgba/Chrono Trigger.srm", in: root)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .retroarch, roms: [rom(id: 7, fileName: "Chrono Trigger.sfc")]
        )

        let scan = try #require(try useCase.execute(for: .retroarch))

        #expect(scan.matched.map(\.romId) == [7])
        #expect(scan.unmatchedFileNames.isEmpty)
    }

    /// The Manic path from issue #144, where the level below `saves` is the
    /// system for most cores and the core name for n64.
    @Test func findsManicSavesUnderBothSystemAndCoreFolders() throws {
        let root = makeRoot()
        write("3DS/sdmc/saves/gba/Pokemon Emerald.sav", in: root)
        write("3DS/sdmc/saves/Mupen64Plus-Next/Mario 64.srm", in: root)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .manicEmu,
            roms: [rom(id: 1, fileName: "Pokemon Emerald.gba"), rom(id: 2, fileName: "Mario 64.z64")]
        )

        let scan = try #require(try useCase.execute(for: .manicEmu))

        #expect(Set(scan.matched.map(\.romId)) == [1, 2])
    }

    /// Delta names a save after the SHA-1 the deep link resolves, so a scan can
    /// only match ROMs whose identifier is already known.
    @Test func matchesDeltaSavesByCachedIdentifier() throws {
        let root = makeRoot()
        let sha1 = "4f2b8c1d9e0a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
        write("Database/\(sha1).sav", in: root)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .delta,
            roms: [rom(id: 3, fileName: "Zelda.gba")],
            identifiers: [3: sha1]
        )

        let scan = try #require(try useCase.execute(for: .delta))

        #expect(scan.matched.map(\.romId) == [3])
    }

    /// Without a cached identifier there is nothing to match against, and the
    /// file has to be reported as unmatched rather than silently dropped.
    @Test func reportsDeltaSavesWithoutACachedIdentifier() throws {
        let root = makeRoot()
        write("Database/deadbeef00112233445566778899aabbccddeeff.sav", in: root)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .delta, roms: [rom(id: 3, fileName: "Zelda.gba")]
        )

        let scan = try #require(try useCase.execute(for: .delta))

        #expect(scan.matched.isEmpty)
        #expect(scan.unmatchedFileNames.count == 1)
    }

    // MARK: - When the hints are wrong

    /// The whole reason the paths are hints: an app that moved its files must
    /// still be found, or the feature fails silently.
    @Test func fallsBackToWalkingTheFolderWhenNoHintMatches() throws {
        let root = makeRoot()
        write("SomewhereElse/Chrono Trigger.srm", in: root)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .retroarch, roms: [rom(id: 7, fileName: "Chrono Trigger.sfc")]
        )

        let scan = try #require(try useCase.execute(for: .retroarch))

        #expect(scan.matched.map(\.romId) == [7])
    }

    /// A folder deeper than the layout allows is not descended into, so a scan
    /// cannot wander through an entire ROM collection.
    @Test func doesNotDescendPastTheDepthLimit() throws {
        let root = makeRoot()
        write("a/b/c/d/e/Chrono Trigger.srm", in: root)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .retroarch, roms: [rom(id: 7, fileName: "Chrono Trigger.sfc")]
        )

        let scan = try #require(try useCase.execute(for: .retroarch))

        #expect(scan.matched.isEmpty)
    }

    // MARK: - What is not a save

    @Test func ignoresRomsAndArtworkBesideTheSave() throws {
        let root = makeRoot()
        let sha1 = "4f2b8c1d9e0a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
        write("Database/\(sha1).sav", in: root)
        write("Database/\(sha1).gba", in: root)
        write("Database/\(sha1).png", in: root)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .delta,
            roms: [rom(id: 3, fileName: "Zelda.gba")], identifiers: [3: sha1]
        )

        let scan = try #require(try useCase.execute(for: .delta))

        #expect(scan.matched.count == 1)
        #expect(scan.matched.first?.fileName == "\(sha1).sav")
        #expect(scan.unmatchedFileNames.isEmpty)
    }

    /// An empty file is not a save. Offering to upload one over a real save on
    /// the server would lose a game.
    @Test func ignoresEmptySaveFiles() throws {
        let root = makeRoot()
        write("RetroArch/saves/mgba/Chrono Trigger.srm", in: root, bytes: 0)
        let (useCase, _) = makeUseCase(
            root: root, emulator: .retroarch, roms: [rom(id: 7, fileName: "Chrono Trigger.sfc")]
        )

        let scan = try #require(try useCase.execute(for: .retroarch))

        #expect(scan.matched.isEmpty)
    }

    // MARK: - No grant

    @Test func returnsNothingWithoutAGrantedFolder() throws {
        let useCase = ScanExternalSavesUseCase(
            folderStore: FakeFolderStore(), localROMs: FakeLocalROMs(), handoffStore: FakeHandoffStore()
        )

        #expect(try useCase.execute(for: .retroarch) == nil)
    }

    /// A bookmark that resolved but whose folder moved still scans; the staleness
    /// is passed on so the screen can say so.
    @Test func reportsAStaleGrant() throws {
        let root = makeRoot()
        write("RetroArch/saves/mgba/Chrono Trigger.srm", in: root)
        let (useCase, folders) = makeUseCase(
            root: root, emulator: .retroarch, roms: [rom(id: 7, fileName: "Chrono Trigger.sfc")]
        )
        folders.stale.insert(.retroarch)

        let scan = try #require(try useCase.execute(for: .retroarch))

        #expect(scan.isStale)
        #expect(scan.matched.count == 1)
    }
}
