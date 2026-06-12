import Foundation

/// Represents a ROM that has been downloaded to the local device
struct DownloadedROM: Identifiable, Codable, Equatable, Hashable {
    let id: Int  // ROM ID from server
    let name: String
    let platformName: String
    let platformSlug: String
    let downloadedAt: Date
    var totalSizeBytes: Int64
    let localDirectory: String  // Path relative to ROMs directory
    var files: [DownloadedROMFile]
    let urlCover: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: downloadedAt, relativeTo: Date())
    }

    /// Full path to the ROM directory
    func fullPath(romsBaseURL: URL) -> URL {
        romsBaseURL.appendingPathComponent(localDirectory)
    }

    static func == (lhs: DownloadedROM, rhs: DownloadedROM) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Convert DownloadedROM to Rom for use with EmulatorView
    func toRom() -> Rom {
        return Rom(
            id: id,
            name: name,
            platformId: 0, // Not available in DownloadedROM
            urlCover: urlCover,
            isFavourite: false,
            hasRetroAchievements: false,
            isPlayable: true,
            fileName: files.first?.fileName,
            platformSlug: platformSlug
        )
    }
}

/// Represents a single file within a downloaded ROM
struct DownloadedROMFile: Identifiable, Codable, Equatable {
    let id: UUID
    let fileName: String
    let fileSizeBytes: Int64
    let md5Hash: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        fileSizeBytes: Int64,
        md5Hash: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.md5Hash = md5Hash
    }

    static func == (lhs: DownloadedROMFile, rhs: DownloadedROMFile) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Metadata structure stored in .metadata.json files
struct ROMMetadata: Codable {
    let romId: Int
    let romName: String
    let platformName: String
    let platformSlug: String
    let downloadedAt: Date
    let files: [ROMFileMetadata]
    let urlCover: String?
}

struct ROMFileMetadata: Codable {
    let fileName: String
    let fileSizeBytes: Int64
    let md5Hash: String?
}
