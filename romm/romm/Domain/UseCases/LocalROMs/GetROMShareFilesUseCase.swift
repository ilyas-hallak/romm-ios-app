import Foundation

protocol PGetROMShareFilesUseCase {
    func execute(rom: DownloadedROM) -> (files: [URL], tempDirectory: URL?)
}

final class GetROMShareFilesUseCase: PGetROMShareFilesUseCase {
    private let localROMRepository: PLocalROMRepository

    init(localROMRepository: PLocalROMRepository) {
        self.localROMRepository = localROMRepository
    }

    func execute(rom: DownloadedROM) -> (files: [URL], tempDirectory: URL?) {
        let romsBaseURL = localROMRepository.romsBaseURL
        let fileManager = FileManager.default
        let shareDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ROMShare-\(UUID().uuidString)")
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
