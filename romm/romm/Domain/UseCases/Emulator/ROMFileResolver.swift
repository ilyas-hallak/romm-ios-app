import Foundation
import ZIPFoundation
import SWCompression

enum DeltaGameType: String, CaseIterable {
    case gba
    case snes
    case genesis
    case nes
    case gbc
    case n64
    case ds
}

enum ROMFileResolverError: Error, LocalizedError {
    case noMatchingFile(gameType: DeltaGameType)
    case noMatchingExtension
    case directoryNotFound(path: String)
    case directoryEmpty(path: String, contents: String)
    case unsupportedArchive(fileName: String)

    var errorDescription: String? {
        switch self {
        case .noMatchingFile(let gameType):
            return "No \(gameType.rawValue.uppercased()) file found. Please re-download the ROM."
        case .noMatchingExtension:
            return "No compatible ROM file found. Please re-download the ROM."
        case .directoryNotFound(let path):
            return "ROM directory not found:\n\(URL(fileURLWithPath: path).lastPathComponent)"
        case .directoryEmpty(let path, let contents):
            return "No ROM file in directory:\n\(URL(fileURLWithPath: path).lastPathComponent)\nFound: \(contents.isEmpty ? "(empty)" : contents)"
        case .unsupportedArchive(let fileName):
            return "Archive format not supported: \(fileName)\nPlease use .gbc / .gb / .zip format on the server."
        }
    }
}

protocol PROMFileResolver {
    func resolve(rom: DownloadedROM, baseURL: URL, gameType: DeltaGameType) throws -> URL
    func resolve(rom: DownloadedROM, baseURL: URL, allowedExtensions: Set<String>) throws -> URL
}

final class ROMFileResolver: PROMFileResolver {

    private let logger = Logger.emulator
    private let fileSystem: PFileSystemService

    private let extensions: [DeltaGameType: Set<String>] = [
        .gba: ["gba"],
        .snes: ["smc", "sfc", "fig", "swc", "snes", "mgd"],
        .genesis: ["md", "gen", "smd", "bin", "sg", "sms"],
        .nes: ["nes", "fds", "unf", "unif"],
        .gbc: ["gbc", "gb", "cgb", "sgb"],
        .n64: ["n64", "z64", "v64", "rom"],
        .ds: ["nds", "dsi", "ids", "srl"]
    ]

    init(fileSystem: PFileSystemService) {
        self.fileSystem = fileSystem
    }

    func resolve(rom: DownloadedROM, baseURL: URL, gameType: DeltaGameType) throws -> URL {
        let allowed = extensions[gameType] ?? []
        do {
            return try resolveInternal(rom: rom, baseURL: baseURL, allowed: allowed)
        } catch ROMFileResolverError.noMatchingExtension {
            throw ROMFileResolverError.noMatchingFile(gameType: gameType)
        }
    }

    func resolve(rom: DownloadedROM, baseURL: URL, allowedExtensions: Set<String>) throws -> URL {
        return try resolveInternal(rom: rom, baseURL: baseURL, allowed: allowedExtensions)
    }

    private func resolveInternal(rom: DownloadedROM, baseURL: URL, allowed: Set<String>) throws -> URL {
        let available = rom.files.map { $0.fileName }
        logger.debug("[ROMFileResolver] allowed=\(allowed) files=\(available)")

        if let direct = rom.files.first(where: { allowed.contains(($0.fileName as NSString).pathExtension.lowercased()) }) {
            return try locate(file: direct.fileName, rom: rom, baseURL: baseURL)
        }

        if let zipFile = rom.files.first(where: { ($0.fileName as NSString).pathExtension.lowercased() == "zip" }) {
            let zipURL = try locate(file: zipFile.fileName, rom: rom, baseURL: baseURL)
            return try extractROM(from: zipURL, allowed: allowed)
        }

        if let sevenZipFile = rom.files.first(where: { ($0.fileName as NSString).pathExtension.lowercased() == "7z" }) {
            let sevenZipURL = try locate(file: sevenZipFile.fileName, rom: rom, baseURL: baseURL)
            return try extractSevenZipROM(from: sevenZipURL, allowed: allowed)
        }

        // Fallback: scan the ROM directory directly (handles old downloads with empty files metadata)
        let romDir = baseURL.appendingPathComponent(rom.localDirectory, isDirectory: true)
        let dirExists = fileSystem.fileExists(at: romDir)
        logger.debug("[ROMFileResolver] fallback scan dir=\(romDir.path) exists=\(dirExists)")
        if let contents = try? fileSystem.contentsOfDirectory(at: romDir, skipHidden: false) {
            let names = contents.map { $0.lastPathComponent }
            logger.debug("[ROMFileResolver] dir contents: \(names)")
            if let match = contents.first(where: { allowed.contains($0.pathExtension.lowercased()) }) {
                logger.debug("[ROMFileResolver] fallback dir scan found: \(match.path)")
                return match
            }
            if let zipFile = contents.first(where: { $0.pathExtension.lowercased() == "zip" }) {
                return try extractROM(from: zipFile, allowed: allowed)
            }
            if let sevenZipFile = contents.first(where: { $0.pathExtension.lowercased() == "7z" }) {
                return try extractSevenZipROM(from: sevenZipFile, allowed: allowed)
            }
            throw ROMFileResolverError.directoryEmpty(
                path: romDir.path,
                contents: names.prefix(5).joined(separator: ", ")
            )
        }

        throw ROMFileResolverError.directoryNotFound(path: romDir.path)
    }

    private func locate(file fileName: String, rom: DownloadedROM, baseURL: URL) throws -> URL {
        let primary = baseURL
            .appendingPathComponent(rom.localDirectory, isDirectory: true)
            .appendingPathComponent(fileName)
        if fileSystem.fileExists(at: primary) {
            return primary
        }
        if let platformDirs = try? fileSystem.contentsOfDirectory(at: baseURL, skipHidden: true) {
            for platformDir in platformDirs {
                let candidate = platformDir
                    .appendingPathComponent(rom.name, isDirectory: true)
                    .appendingPathComponent(fileName)
                if fileSystem.fileExists(at: candidate) {
                    return candidate
                }
            }
        }
        return primary
    }

    private func extractROM(from zipURL: URL, allowed: Set<String>) throws -> URL {
        let cacheDir = fileSystem.cachesDirectory()
            .appendingPathComponent("UnzippedROMs", isDirectory: true)
            .appendingPathComponent(zipURL.deletingPathExtension().lastPathComponent, isDirectory: true)

        if fileSystem.fileExists(at: cacheDir),
           let existing = firstROM(in: cacheDir, allowed: allowed) {
            logger.debug("[ROMFileResolver] cached unzip hit: \(existing.path)")
            return existing
        }

        try? fileSystem.removeItem(at: cacheDir)
        try fileSystem.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let archive = try Archive(url: zipURL, accessMode: .read)
        for entry in archive where allowed.contains((entry.path as NSString).pathExtension.lowercased()) {
            let dest = cacheDir.appendingPathComponent((entry.path as NSString).lastPathComponent)
            _ = try archive.extract(entry, to: dest)
            logger.debug("[ROMFileResolver] extracted \(entry.path) -> \(dest.path)")
            return dest
        }

        throw ROMFileResolverError.noMatchingExtension
    }

    private func extractSevenZipROM(from sevenZipURL: URL, allowed: Set<String>) throws -> URL {
        let cacheDir = fileSystem.cachesDirectory()
            .appendingPathComponent("UnzippedROMs", isDirectory: true)
            .appendingPathComponent(sevenZipURL.deletingPathExtension().lastPathComponent, isDirectory: true)

        if fileSystem.fileExists(at: cacheDir),
           let existing = firstROM(in: cacheDir, allowed: allowed) {
            logger.debug("[ROMFileResolver] cached 7z hit: \(existing.path)")
            return existing
        }

        try? fileSystem.removeItem(at: cacheDir)
        try fileSystem.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let data = try Data(contentsOf: sevenZipURL)
        let entries = try SevenZipContainer.open(container: data)
        for entry in entries {
            let entryName = entry.info.name ?? ""
            let ext = (entryName as NSString).pathExtension.lowercased()
            guard allowed.contains(ext), let entryData = entry.data else { continue }
            let dest = cacheDir.appendingPathComponent((entryName as NSString).lastPathComponent)
            try entryData.write(to: dest)
            logger.debug("[ROMFileResolver] extracted 7z \(entryName) -> \(dest.path)")
            return dest
        }

        throw ROMFileResolverError.noMatchingExtension
    }

    private func firstROM(in dir: URL, allowed: Set<String>) -> URL? {
        guard let contents = try? fileSystem.contentsOfDirectory(at: dir, skipHidden: true) else { return nil }
        return contents.first { allowed.contains($0.pathExtension.lowercased()) }
    }

}
