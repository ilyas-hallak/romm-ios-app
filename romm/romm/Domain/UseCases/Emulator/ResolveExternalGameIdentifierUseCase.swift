import Foundation

/// What an external emulator needs to be handed a ROM and to find it again later.
struct ExternalGameHandoff: Sendable {
    /// How the target app addresses this game once it has imported it.
    let gameIdentifier: String
    /// The single ROM file to hand over, when it differs from what is stored on
    /// disk. Nil means the ROM's own files go over unchanged.
    let unpackedROMURL: URL?
}

enum ExternalGameIdentifierError: Error, LocalizedError {
    case unsupportedPlatform(platformName: String, emulatorName: String)
    case noROMFile

    var errorDescription: String? {
        switch self {
        case .unsupportedPlatform(let platformName, let emulatorName):
            return "\(emulatorName) cannot play \(platformName) ROMs. Switch Play back to the built-in emulator in Settings."
        case .noROMFile:
            return "No ROM file found. Please re-download this ROM."
        }
    }
}

/// Works out how a target app will address a ROM, and which file it should get.
///
/// The two answers come from the same place: an emulator that identifies a game
/// by its content has to be handed exactly the file that was hashed, otherwise
/// the deep link points at something the app never imported.
protocol PResolveExternalGameIdentifierUseCase {
    func execute(
        rom: DownloadedROM,
        baseURL: URL,
        emulator: any PExternalEmulator
    ) async throws -> ExternalGameHandoff
}

final class ResolveExternalGameIdentifierUseCase: PResolveExternalGameIdentifierUseCase {

    /// A resolver, not a use case, so injecting it keeps use cases free of each
    /// other. It already unpacks zip and 7z into `Caches/UnzippedROMs` and caches
    /// the result, which is exactly what a content hash needs.
    private let resolver: PROMFileResolver

    init(resolver: PROMFileResolver) {
        self.resolver = resolver
    }

    func execute(
        rom: DownloadedROM,
        baseURL: URL,
        emulator: any PExternalEmulator
    ) async throws -> ExternalGameHandoff {
        let kind = emulator.identifierKind

        // RetroArch resolves by name against its own library, so nothing has to
        // be read off disk at all.
        if kind == .fileName && !emulator.wantsUnpackedROM {
            guard let fileName = Self.primaryFileName(of: rom) else {
                throw ExternalGameIdentifierError.noROMFile
            }
            return ExternalGameHandoff(gameIdentifier: fileName, unpackedROMURL: nil)
        }

        guard let gameType = PlatformSlugToGameType.map(rom.platformSlug) else {
            throw ExternalGameIdentifierError.unsupportedPlatform(
                platformName: rom.platformName,
                emulatorName: emulator.displayName
            )
        }

        // Unpacking and hashing a ROM is slow enough to be felt on the Play tap,
        // so it stays off the main actor.
        let resolver = self.resolver
        let wantsUnpackedROM = emulator.wantsUnpackedROM
        return try await Task.detached(priority: .userInitiated) {
            let romURL = try resolver.resolve(rom: rom, baseURL: baseURL, gameType: gameType)
            let identifier: String
            switch kind {
            case .fileName:
                identifier = romURL.lastPathComponent
            case .sha1OfROMData:
                identifier = try FileHashing.sha1(ofFileAt: romURL)
            }
            return ExternalGameHandoff(
                gameIdentifier: identifier,
                unpackedROMURL: wantsUnpackedROM ? romURL : nil
            )
        }.value
    }

    // MARK: - Private

    /// The file an external emulator should be pointed at.
    ///
    /// Disc-based ROMs ship a playlist or sheet next to the data tracks, and that
    /// is the file emulators expect, a raw `.bin` boots nothing.
    static func primaryFileName(of rom: DownloadedROM) -> String? {
        let preferredExtensions = ["m3u", "cue"]
        for ext in preferredExtensions {
            if let match = rom.files.first(where: { $0.fileName.lowercased().hasSuffix(".\(ext)") }) {
                return match.fileName
            }
        }
        return rom.files.first?.fileName
    }
}
