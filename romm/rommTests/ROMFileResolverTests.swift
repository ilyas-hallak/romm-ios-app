import Testing
import Foundation
@testable import romm

/// Answers "yes" for whatever paths the test declares present, so the resolver
/// can be exercised without touching the disk.
private final class StubFileSystem: PFileSystemService {
    var presentFileNames: Set<String> = []

    func fileExists(at url: URL) -> Bool { presentFileNames.contains(url.lastPathComponent) }
    func documentsDirectory() -> URL { URL(fileURLWithPath: "/tmp") }
    func cachesDirectory() -> URL { URL(fileURLWithPath: "/tmp") }
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func contentsOfDirectory(at url: URL, skipHidden: Bool) throws -> [URL] { [] }
    func removeItem(at url: URL) throws {}
    func write(_ data: Data, to url: URL) throws {}
}

struct ROMFileResolverTests {

    private func makeROM(files: [String]) -> DownloadedROM {
        DownloadedROM(
            id: 1, name: "Test", platformName: "Game Boy Advance",
            platformSlug: "gba", downloadedAt: Date(), totalSizeBytes: 0,
            localDirectory: "rom1",
            files: files.map {
                DownloadedROMFile(id: UUID(), fileName: $0, fileSizeBytes: 0, md5Hash: nil)
            },
            urlCover: nil
        )
    }

    @Test func picksGBAExtension() throws {
        let rom = makeROM(files: ["readme.txt", "Game.gba"])
        let fileSystem = StubFileSystem()
        fileSystem.presentFileNames = ["Game.gba"]
        let resolver = ROMFileResolver(fileSystem: fileSystem)
        let url = try resolver.resolve(rom: rom, baseURL: URL(fileURLWithPath: "/tmp"), gameType: .gba)
        #expect(url.lastPathComponent == "Game.gba")
    }

    @Test func throwsWhenNoMatch() {
        let rom = makeROM(files: ["readme.txt"])
        let resolver = ROMFileResolver(fileSystem: StubFileSystem())
        #expect(throws: ROMFileResolverError.self) {
            _ = try resolver.resolve(rom: rom, baseURL: URL(fileURLWithPath: "/tmp"), gameType: .gba)
        }
    }
}
