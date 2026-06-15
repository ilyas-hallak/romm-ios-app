import Foundation

protocol PLocalROMRepository {
    /// Gets all downloaded ROMs from local storage
    func getAllDownloadedROMs() throws -> [DownloadedROM]

    /// Gets downloaded ROMs grouped by platform
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]]

    /// Gets a specific downloaded ROM by ID
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM?

    /// Saves a downloaded ROM with its metadata
    func saveDownloadedROM(_ rom: DownloadedROM) throws

    /// Deletes a downloaded ROM and all its files
    func deleteDownloadedROM(_ rom: DownloadedROM) throws

    /// Gets the total size of all downloaded ROMs
    func getTotalDownloadedSize() throws -> Int64

    /// Gets the number of downloaded ROMs
    func getDownloadedROMsCount() throws -> Int

    /// Gets the base URL for ROM storage
    var romsBaseURL: URL { get }
}

class LocalROMRepository: PLocalROMRepository {

    private let fileManager = FileManager.default
    private let metadataFileName = ".metadata.json"

    /// Base directory for all ROM downloads
    /// Structure: Documents/ROMs/{Platform}/{ROM-Name}/
    var romsBaseURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("ROMs")
    }

    init() {
        // Ensure ROMs directory exists
        try? createROMsDirectoryIfNeeded()
    }

    // MARK: - Public Methods

    func getAllDownloadedROMs() throws -> [DownloadedROM] {
        var downloadedROMs: [DownloadedROM] = []

        // Scan all platform directories
        let platformDirs = try fileManager.contentsOfDirectory(
            at: romsBaseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for platformDir in platformDirs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: platformDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }

            // Scan all ROM directories within this platform
            let romDirs = try fileManager.contentsOfDirectory(
                at: platformDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for romDir in romDirs {
                guard fileManager.fileExists(atPath: romDir.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                // Try to load metadata
                if let rom = try? loadROMMetadata(from: romDir) {
                    downloadedROMs.append(rom)
                }
            }
        }

        return downloadedROMs.sorted { $0.downloadedAt > $1.downloadedAt }
    }

    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] {
        let allROMs = try getAllDownloadedROMs()

        var romsByPlatform: [String: [DownloadedROM]] = [:]

        for rom in allROMs {
            if romsByPlatform[rom.platformName] == nil {
                romsByPlatform[rom.platformName] = []
            }
            romsByPlatform[rom.platformName]?.append(rom)
        }

        return romsByPlatform
    }

    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? {
        let allROMs = try getAllDownloadedROMs()
        return allROMs.first { $0.id == id }
    }

    func saveDownloadedROM(_ rom: DownloadedROM) throws {
        let romDirectoryURL = romsBaseURL.appendingPathComponent(rom.localDirectory)

        // Create directory if it doesn't exist
        try fileManager.createDirectory(
            at: romDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Create metadata
        let metadata = ROMMetadata(
            romId: rom.id,
            romName: rom.name,
            platformName: rom.platformName,
            platformSlug: rom.platformSlug,
            downloadedAt: rom.downloadedAt,
            files: rom.files.map { file in
                ROMFileMetadata(
                    fileName: file.fileName,
                    fileSizeBytes: file.fileSizeBytes,
                    md5Hash: file.md5Hash
                )
            }
        )

        // Save metadata to .metadata.json
        let metadataURL = romDirectoryURL.appendingPathComponent(metadataFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataURL)
    }

    func deleteDownloadedROM(_ rom: DownloadedROM) throws {
        let romDirectoryURL = romsBaseURL.appendingPathComponent(rom.localDirectory)
        if fileManager.fileExists(atPath: romDirectoryURL.path) {
            try fileManager.removeItem(at: romDirectoryURL)
        }
    }

    func getTotalDownloadedSize() throws -> Int64 {
        let allROMs = try getAllDownloadedROMs()
        return allROMs.reduce(0) { $0 + $1.totalSizeBytes }
    }

    func getDownloadedROMsCount() throws -> Int {
        return try getAllDownloadedROMs().count
    }

    // MARK: - Private Helper Methods

    private func createROMsDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: romsBaseURL.path) {
            try fileManager.createDirectory(
                at: romsBaseURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func loadROMMetadata(from romDirectory: URL) throws -> DownloadedROM? {
        let metadataURL = romDirectory.appendingPathComponent(metadataFileName)

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        let metadataData = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let metadata = try decoder.decode(ROMMetadata.self, from: metadataData)

        // Calculate actual file sizes
        var totalSize: Int64 = 0
        var downloadedFiles: [DownloadedROMFile] = []

        for fileMetadata in metadata.files {
            let fileURL = romDirectory.appendingPathComponent(fileMetadata.fileName)

            var actualSize = fileMetadata.fileSizeBytes

            // Get actual file size if file exists
            if fileManager.fileExists(atPath: fileURL.path) {
                if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                   let fileSize = attributes[.size] as? Int64 {
                    actualSize = fileSize
                }
            }

            totalSize += actualSize

            downloadedFiles.append(DownloadedROMFile(
                fileName: fileMetadata.fileName,
                fileSizeBytes: actualSize,
                md5Hash: fileMetadata.md5Hash
            ))
        }

        let standardizedRomDir = romDirectory.standardizedFileURL.path
        let standardizedBase = romsBaseURL.standardizedFileURL.path
        let relativePath: String
        if standardizedRomDir.hasPrefix(standardizedBase + "/") {
            relativePath = String(standardizedRomDir.dropFirst(standardizedBase.count + 1))
        } else {
            relativePath = romDirectory.lastPathComponent
        }

        return DownloadedROM(
            id: metadata.romId,
            name: metadata.romName,
            platformName: metadata.platformName,
            platformSlug: metadata.platformSlug,
            downloadedAt: metadata.downloadedAt,
            totalSizeBytes: totalSize,
            localDirectory: relativePath,
            files: downloadedFiles
        )
    }

    /// Creates the directory path for a ROM
    /// Returns: Relative path like "Game Boy/Pokemon Red"
    static func createROMDirectoryPath(platformName: String, romName: String) -> String {
        let sanitizedPlatform = sanitizePathComponent(platformName)
        let sanitizedROM = sanitizePathComponent(romName)
        return "\(sanitizedPlatform)/\(sanitizedROM)"
    }

    private static func sanitizePathComponent(_ name: String) -> String {
        // Colon ':' is translated to '/' on Apple HFS+ legacy paths, causing directory creation failures
        var result = name.replacingOccurrences(of: "/", with: "-")
        result = result.replacingOccurrences(of: ":", with: "-")
        return result
    }
}
