import Testing
import Foundation
@testable import romm

/// Stands in for the real resolver so the tests do not need a ROM library on
/// disk. `resolvedURL` is whatever the resolver would have unpacked.
private final class FakeROMFileResolver: PROMFileResolver, @unchecked Sendable {
    var resolvedURL: URL?
    var error: Error?
    private(set) var requestedGameType: DeltaGameType?

    func resolve(rom: DownloadedROM, baseURL: URL, gameType: DeltaGameType) throws -> URL {
        requestedGameType = gameType
        if let error { throw error }
        guard let resolvedURL else { throw ROMFileResolverError.noMatchingExtension }
        return resolvedURL
    }

    func resolve(rom: DownloadedROM, baseURL: URL, allowedExtensions: Set<String>) throws -> URL {
        if let error { throw error }
        guard let resolvedURL else { throw ROMFileResolverError.noMatchingExtension }
        return resolvedURL
    }
}

private func makeROM(
    platformSlug: String = "gba",
    fileNames: [String] = ["Game.gba"]
) -> DownloadedROM {
    DownloadedROM(
        id: 1,
        name: "Game",
        platformName: "Game Boy Advance",
        platformSlug: platformSlug,
        downloadedAt: Date(timeIntervalSince1970: 0),
        totalSizeBytes: 0,
        localDirectory: "gba/Game",
        files: fileNames.map { DownloadedROMFile(fileName: $0, fileSizeBytes: 0) },
        urlCover: nil
    )
}

struct ResolveExternalGameIdentifierUseCaseTests {

    private let baseURL = URL(fileURLWithPath: "/tmp/roms")

    // MARK: - File name targets

    @Test func retroArchGetsThePlainFileNameWithoutTouchingDisk() async throws {
        let resolver = FakeROMFileResolver()
        let useCase = ResolveExternalGameIdentifierUseCase(resolver: resolver)

        let handoff = try await useCase.execute(
            rom: makeROM(),
            baseURL: baseURL,
            emulator: RetroArchExternalEmulator()
        )

        #expect(handoff.gameIdentifier == "Game.gba")
        #expect(handoff.unpackedROMURL == nil)
        // Nothing was resolved, so nothing was read or unpacked.
        #expect(resolver.requestedGameType == nil)
    }

    /// Disc-based ROMs ship a playlist next to the data tracks, and that is the
    /// file an emulator has to be pointed at. A raw .bin boots nothing.
    @Test func prefersAPlaylistOverASheetOverTheFirstFile() async throws {
        let useCase = ResolveExternalGameIdentifierUseCase(resolver: FakeROMFileResolver())

        let withPlaylist = try await useCase.execute(
            rom: makeROM(fileNames: ["Game (Disc 1).bin", "Game.cue", "Game.m3u"]),
            baseURL: baseURL,
            emulator: RetroArchExternalEmulator()
        )
        #expect(withPlaylist.gameIdentifier == "Game.m3u")

        let withSheet = try await useCase.execute(
            rom: makeROM(fileNames: ["Game (Disc 1).bin", "Game.cue"]),
            baseURL: baseURL,
            emulator: RetroArchExternalEmulator()
        )
        #expect(withSheet.gameIdentifier == "Game.cue")

        let plain = try await useCase.execute(
            rom: makeROM(fileNames: ["Game.gba"]),
            baseURL: baseURL,
            emulator: RetroArchExternalEmulator()
        )
        #expect(plain.gameIdentifier == "Game.gba")
    }

    @Test func reportsAROMWithoutAnyFiles() async {
        let useCase = ResolveExternalGameIdentifierUseCase(resolver: FakeROMFileResolver())

        await #expect(throws: ExternalGameIdentifierError.self) {
            try await useCase.execute(
                rom: makeROM(fileNames: []),
                baseURL: baseURL,
                emulator: RetroArchExternalEmulator()
            )
        }
    }

    // MARK: - Content hash targets

    @Test func deltaGetsTheSHA1OfTheResolvedFile() async throws {
        let romURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ResolveIdentifierTests-\(UUID().uuidString).gba")
        try Data("abc".utf8).write(to: romURL)
        defer { try? FileManager.default.removeItem(at: romURL) }

        let resolver = FakeROMFileResolver()
        resolver.resolvedURL = romURL
        let useCase = ResolveExternalGameIdentifierUseCase(resolver: resolver)

        let handoff = try await useCase.execute(
            rom: makeROM(),
            baseURL: baseURL,
            emulator: DeltaExternalEmulator()
        )

        #expect(handoff.gameIdentifier == "a9993e364706816aba3e25717850c26c9cd0d89d")
        // Delta has to receive exactly the file that was hashed.
        #expect(handoff.unpackedROMURL == romURL)
        #expect(resolver.requestedGameType == .gba)
    }

    /// Delta only runs the systems DeltaGameType covers. Saying so beats handing
    /// the ROM over and having Delta silently refuse the deep link later.
    @Test func rejectsAPlatformTheEmulatorCannotPlay() async {
        let resolver = FakeROMFileResolver()
        let useCase = ResolveExternalGameIdentifierUseCase(resolver: resolver)

        await #expect(throws: ExternalGameIdentifierError.self) {
            try await useCase.execute(
                rom: makeROM(platformSlug: "ps", fileNames: ["Game.cue"]),
                baseURL: baseURL,
                emulator: DeltaExternalEmulator()
            )
        }
        #expect(resolver.requestedGameType == nil)
    }

    @Test func propagatesAResolverFailure() async {
        let resolver = FakeROMFileResolver()
        resolver.error = ROMFileResolverError.noMatchingExtension
        let useCase = ResolveExternalGameIdentifierUseCase(resolver: resolver)

        await #expect(throws: (any Error).self) {
            try await useCase.execute(
                rom: makeROM(),
                baseURL: baseURL,
                emulator: DeltaExternalEmulator()
            )
        }
    }
}
