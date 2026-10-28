//
//  GetROMShareFilesUseCaseTests.swift
//  rommTests
//
//  Runs against real, throwaway directories on disk, since where the copy lands
//  decides whether the receiving app can open it in place.
//

import Foundation
import Testing
@testable import romm

struct GetROMShareFilesUseCaseTests {
    private let fileManager = FileManager.default

    private func makeRoot() -> URL {
        let root = fileManager.temporaryDirectory.appendingPathComponent("rom-share-tests-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeFile(named name: String, in directory: URL) throws -> URL {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x42, count: 16).write(to: url)
        return url
    }

    /// From the temp directory iOS only drops a copy into RetroArch's Inbox,
    /// which RetroArch never imports (#229).
    @Test func stagesTheCopyInAHiddenFolderInDocuments() throws {
        let source = try writeFile(named: "Game (USA).zip", in: makeRoot())
        let useCase = GetROMShareFilesUseCase(localROMRepository: StubLocalROMs(romsBaseURL: makeRoot()))

        let result = useCase.execute(fileAt: source)
        defer { result.tempDirectory.map { try? fileManager.removeItem(at: $0) } }

        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let staged = try #require(result.files.first)
        #expect(staged.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == documents.standardizedFileURL)
        #expect(staged.deletingLastPathComponent().lastPathComponent.hasPrefix("."))
        #expect(fileManager.fileExists(atPath: staged.path))
    }

    @Test func excludesTheCopyFromBackup() throws {
        let root = makeRoot()
        let source = try writeFile(named: "Game.gba", in: makeRoot())
        let useCase = GetROMShareFilesUseCase(localROMRepository: StubLocalROMs(romsBaseURL: root), shareRootDirectory: root)

        let directory = try #require(useCase.execute(fileAt: source).tempDirectory)

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func copiesEveryFileOfADownloadedROM() throws {
        let romsBase = makeRoot()
        let romDirectory = romsBase.appendingPathComponent("psx/Game")
        _ = try writeFile(named: "Game.cue", in: romDirectory)
        _ = try writeFile(named: "Game.bin", in: romDirectory)
        let rom = DownloadedROM(
            id: 1, name: "Game", platformName: "PlayStation", platformSlug: "psx",
            downloadedAt: Date(), totalSizeBytes: 32, localDirectory: "psx/Game",
            files: [DownloadedROMFile(fileName: "Game.cue", fileSizeBytes: 16, md5Hash: nil),
                    DownloadedROMFile(fileName: "Game.bin", fileSizeBytes: 16, md5Hash: nil)],
            urlCover: nil
        )
        let useCase = GetROMShareFilesUseCase(localROMRepository: StubLocalROMs(romsBaseURL: romsBase), shareRootDirectory: makeRoot())

        let result = useCase.execute(rom: rom)

        #expect(result.files.map(\.lastPathComponent) == ["Game.cue", "Game.bin"])
        #expect(result.files.allSatisfy { fileManager.fileExists(atPath: $0.path) })
    }

    @Test func nextShareRemovesOnlyStaleCopies() throws {
        let root = makeRoot()
        let prefix = GetROMShareFilesUseCase.shareDirectoryPrefix
        let stale = root.appendingPathComponent("\(prefix)stale")
        let fresh = root.appendingPathComponent("\(prefix)fresh")
        let unrelated = root.appendingPathComponent("roms")
        for directory in [stale, fresh, unrelated] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let old = Date().addingTimeInterval(-GetROMShareFilesUseCase.shareDirectoryLifetime - 60)
        try fileManager.setAttributes([.creationDate: old], ofItemAtPath: stale.path)
        try fileManager.setAttributes([.creationDate: old], ofItemAtPath: unrelated.path)
        let source = try writeFile(named: "Game.gba", in: makeRoot())
        let useCase = GetROMShareFilesUseCase(localROMRepository: StubLocalROMs(romsBaseURL: root), shareRootDirectory: root)

        _ = useCase.execute(fileAt: source)

        #expect(!fileManager.fileExists(atPath: stale.path))
        #expect(fileManager.fileExists(atPath: fresh.path))
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }
}

private struct StubLocalROMs: PLocalROMRepository {
    let romsBaseURL: URL

    func getAllDownloadedROMs() throws -> [DownloadedROM] { [] }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { nil }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { 0 }
}
