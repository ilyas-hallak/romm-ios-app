import Foundation

protocol PGetROMShareFilesUseCase {
    func execute(rom: DownloadedROM) -> (files: [URL], tempDirectory: URL?)
    /// Stages a single already resolved ROM file, e.g. one unpacked out of an
    /// archive for an emulator that cannot read archives.
    func execute(fileAt url: URL) -> (files: [URL], tempDirectory: URL?)
}

final class GetROMShareFilesUseCase: PGetROMShareFilesUseCase {
    /// The leading dot keeps the copies out of the Files app.
    static let shareDirectoryPrefix = ".ROMShare-"
    /// How long a share copy is kept around before the next share may delete it.
    static let shareDirectoryLifetime: TimeInterval = 60 * 60

    private let localROMRepository: PLocalROMRepository
    private let shareRootDirectory: URL

    /// The copies have to live in Documents, not in the temp directory: only from
    /// there iOS lets the receiving app open the file in place. From tmp it drops
    /// a copy into the receiver's `Documents/Inbox` instead, which RetroArch
    /// never imports.
    init(
        localROMRepository: PLocalROMRepository,
        shareRootDirectory: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) {
        self.localROMRepository = localROMRepository
        self.shareRootDirectory = shareRootDirectory
    }

    func execute(rom: DownloadedROM) -> (files: [URL], tempDirectory: URL?) {
        let romsBaseURL = localROMRepository.romsBaseURL
        let fileManager = FileManager.default
        let shareDirectory = makeShareDirectory(fileManager: fileManager)

        var romDirectoryURL = romsBaseURL.appendingPathComponent(rom.localDirectory)
        if !fileManager.fileExists(atPath: romDirectoryURL.path) {
            guard let actual = findActualPath(romsBaseURL: romsBaseURL, romName: rom.name, fileManager: fileManager) else {
                return ([], nil)
            }
            romDirectoryURL = actual
        }

        let urls = rom.files.compactMap {
            copy(romDirectoryURL.appendingPathComponent($0.fileName), into: shareDirectory, fileManager: fileManager)
        }

        return (urls, urls.isEmpty ? nil : shareDirectory)
    }

    func execute(fileAt url: URL) -> (files: [URL], tempDirectory: URL?) {
        let fileManager = FileManager.default
        let shareDirectory = makeShareDirectory(fileManager: fileManager)
        guard let staged = copy(url, into: shareDirectory, fileManager: fileManager) else {
            return ([], nil)
        }
        return ([staged], shareDirectory)
    }

    private func makeShareDirectory(fileManager: FileManager) -> URL {
        purgeStaleShareDirectories(fileManager: fileManager)
        var shareDirectory = shareRootDirectory
            .appendingPathComponent("\(Self.shareDirectoryPrefix)\(UUID().uuidString)")
        try? fileManager.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? shareDirectory.setResourceValues(resourceValues)
        return shareDirectory
    }

    /// The receiving app needs to be able to read the copy, which the ROM folder's
    /// own permissions do not guarantee.
    private func copy(_ source: URL, into directory: URL, fileManager: FileManager) -> URL? {
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        do {
            try fileManager.copyItem(at: source, to: destination)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
            return destination
        } catch {
            return nil
        }
    }

    /// Removes leftovers from earlier shares.
    ///
    /// The copy cannot be deleted right after handing it over: apps that open
    /// documents in place (RetroArch) read straight from this directory while
    /// importing. So the cleanup is deferred to the next share instead, and only
    /// touches directories old enough that no import can still be running.
    private func purgeStaleShareDirectories(fileManager: FileManager) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: shareRootDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Self.shareDirectoryLifetime)
        for entry in entries where entry.lastPathComponent.hasPrefix(Self.shareDirectoryPrefix) {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            guard let created, created < cutoff else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    private func findActualPath(romsBaseURL: URL, romName: String, fileManager: FileManager) -> URL? {
        guard let platformDirs = try? fileManager.contentsOfDirectory(
            at: romsBaseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for dir in platformDirs {
            let candidate = dir.appendingPathComponent(romName)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
