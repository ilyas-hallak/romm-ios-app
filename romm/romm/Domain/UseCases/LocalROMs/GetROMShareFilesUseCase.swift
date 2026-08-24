import Foundation

protocol PGetROMShareFilesUseCase {
    func execute(rom: DownloadedROM) -> (files: [URL], tempDirectory: URL?)
}

final class GetROMShareFilesUseCase: PGetROMShareFilesUseCase {
    static let shareDirectoryPrefix = "ROMShare-"
    /// How long a share copy is kept around before the next share may delete it.
    static let shareDirectoryLifetime: TimeInterval = 60 * 60

    private let localROMRepository: PLocalROMRepository

    init(localROMRepository: PLocalROMRepository) {
        self.localROMRepository = localROMRepository
    }

    func execute(rom: DownloadedROM) -> (files: [URL], tempDirectory: URL?) {
        let romsBaseURL = localROMRepository.romsBaseURL
        let fileManager = FileManager.default
        purgeStaleShareDirectories(fileManager: fileManager)
        let shareDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(Self.shareDirectoryPrefix)\(UUID().uuidString)")
        try? fileManager.createDirectory(at: shareDirectory, withIntermediateDirectories: true)

        var romDirectoryURL = romsBaseURL.appendingPathComponent(rom.localDirectory)
        if !fileManager.fileExists(atPath: romDirectoryURL.path) {
            guard let actual = findActualPath(romsBaseURL: romsBaseURL, romName: rom.name, fileManager: fileManager) else {
                return ([], nil)
            }
            romDirectoryURL = actual
        }

        var urls: [URL] = []
        for file in rom.files {
            let src = romDirectoryURL.appendingPathComponent(file.fileName)
            let dst = shareDirectory.appendingPathComponent(file.fileName)
            guard fileManager.fileExists(atPath: src.path) else { continue }
            do {
                try fileManager.copyItem(at: src, to: dst)
                try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dst.path)
                urls.append(dst)
            } catch {}
        }

        return (urls, urls.isEmpty ? nil : shareDirectory)
    }

    /// Removes leftovers from earlier shares.
    ///
    /// The copy cannot be deleted right after handing it over: apps that open
    /// documents in place (RetroArch) read straight from this directory while
    /// importing. So the cleanup is deferred to the next share instead, and only
    /// touches directories old enough that no import can still be running.
    private func purgeStaleShareDirectories(fileManager: FileManager) {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
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
