import Testing
import Foundation
@testable import romm

struct FindROMsByFileStemUseCaseTests {

    private func rom(_ id: Int, files: [String]) -> DownloadedROM {
        DownloadedROM(
            id: id,
            name: "ROM \(id)",
            platformName: "PlayStation",
            platformSlug: "ps",
            downloadedAt: Date(),
            totalSizeBytes: 0,
            localDirectory: "PlayStation/ROM \(id)",
            files: files.map { DownloadedROMFile(fileName: $0, fileSizeBytes: 0) },
            urlCover: nil
        )
    }

    @Test func matchesFileNamesIgnoringExtensionAndCase() throws {
        let repository = FixedLocalROMs(roms: [
            rom(1, files: ["Game.cue", "Game.bin"]),
            rom(2, files: ["game.chd"]),
            rom(3, files: ["Other.iso"]),
            rom(4, files: ["Game.zip"])
        ])

        let owners = try FindROMsByFileStemUseCase(localROMRepository: repository).execute(stem: "Game")

        #expect(owners == [1, 2, 4])
    }
}

private struct FixedLocalROMs: PLocalROMRepository {
    let roms: [DownloadedROM]
    var romsBaseURL: URL { FileManager.default.temporaryDirectory }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { roms }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { roms.first { $0.id == id } }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { roms.count }
}
