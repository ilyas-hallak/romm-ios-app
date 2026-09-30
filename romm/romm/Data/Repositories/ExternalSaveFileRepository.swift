import Foundation

/// Walks the folders the user granted for other emulator apps, reports the
/// files worth matching against this device's ROMs, and writes saves back into
/// them.
final class ExternalSaveFileRepository: PExternalSaveFileRepository {

    /// Where replaced files are kept. Inside our own container rather than
    /// beside the original: a spare copy in the emulator's save folder is a
    /// file that app may well try to load.
    private static let backupDirectoryName = "ExternalSaveBackups"

    private let logger = Logger.emulator
    private let folderStore: PExternalSaveFolderStore
    private let fileManager: FileManager

    init(folderStore: PExternalSaveFolderStore, fileManager: FileManager = .default) {
        self.folderStore = folderStore
        self.fileManager = fileManager
    }

    func emulatorsWithFolder() -> [ExternalEmulatorID] {
        folderStore.grantedEmulators()
    }

    func contents(for emulator: ExternalEmulatorID) -> ExternalSaveFolderContents? {
        guard let layout = emulator.emulator.saveLayout,
              let grant = folderStore.grantedFolder(for: emulator) else { return nil }

        return grant.withAccess { root in
            ExternalSaveFolderContents(
                candidates: candidateURLs(under: root, layout: layout).compactMap(candidate(at:)),
                isStale: grant.isStale
            )
        }
    }

    func readSaves(at urls: [URL], for emulator: ExternalEmulatorID) -> [URL: Data] {
        guard !urls.isEmpty, let grant = folderStore.grantedFolder(for: emulator) else { return [:] }
        return grant.withAccess { _ in
            urls.reduce(into: [URL: Data]()) { contents, url in
                guard let data = try? Data(contentsOf: url) else {
                    logger.warning("Could not read \(url.lastPathComponent) in \(emulator.rawValue)")
                    return
                }
                contents[url] = data
            }
        }
    }

    func destination(
        for emulator: ExternalEmulatorID,
        baseName: String
    ) -> ExternalSaveDestination? {
        guard let layout = emulator.emulator.saveLayout,
              let contents = contents(for: emulator) else { return nil }

        let saves = contents.candidates.filter { layout.batteryKey(forFileName: $0.fileName) != nil }
        // An exact match wins: that file is the one the app reads for this game.
        if let existing = saves.first(where: {
            layout.batteryKey(forFileName: $0.fileName)?.lowercased() == baseName.lowercased()
        }) {
            return ExternalSaveDestination(
                emulator: emulator,
                url: existing.url,
                existingModifiedAt: existing.modifiedAt
            )
        }
        guard let neighbour = saves.first else {
            logger.warning("No save in \(emulator.rawValue)'s folder to model a path on")
            return nil
        }
        let url = neighbour.url
            .deletingLastPathComponent()
            .appendingPathComponent(baseName)
            .appendingPathExtension(fileExtension(of: neighbour.fileName))
        return ExternalSaveDestination(emulator: emulator, url: url, existingModifiedAt: nil)
    }

    func write(_ data: Data, to destination: ExternalSaveDestination, modifiedAt: Date) throws {
        guard let grant = folderStore.grantedFolder(for: destination.emulator) else {
            throw ExternalSaveWriteError.folderNotGranted
        }
        try grant.withAccess { _ in
            if fileManager.fileExists(atPath: destination.url.path) {
                try backUp(destination)
            }
            try data.write(to: destination.url, options: .atomic)
            try? fileManager.setAttributes(
                [.modificationDate: modifiedAt],
                ofItemAtPath: destination.url.path
            )
            logger.info("Wrote \(data.count) bytes to \(destination.emulator.rawValue): "
                + "\(destination.url.lastPathComponent)")
        }
    }

    // MARK: - Private

    /// Copies the file about to be replaced into our own container, under the
    /// time it was replaced so repeated syncs do not overwrite the copy.
    private func backUp(_ destination: ExternalSaveDestination) throws {
        let directory = try backupDirectory(for: destination.emulator)
        let stamp = DateFormatter.backupStamp.string(from: Date())
        let name = destination.url.deletingPathExtension().lastPathComponent
        let target = directory
            .appendingPathComponent("\(name)-\(stamp)")
            .appendingPathExtension(fileExtension(of: destination.url.lastPathComponent))
        try fileManager.copyItem(at: destination.url, to: target)
        logger.info("Backed up \(destination.url.lastPathComponent) to \(target.lastPathComponent)")
    }

    private func backupDirectory(for emulator: ExternalEmulatorID) throws -> URL {
        guard let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ExternalSaveWriteError.noBackupDirectory
        }
        let directory = support
            .appendingPathComponent(Self.backupDirectoryName, isDirectory: true)
            .appendingPathComponent(emulator.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fileExtension(of fileName: String) -> String {
        (fileName as NSString).pathExtension
    }

    /// Files worth looking at, hints first and the whole folder only as a
    /// fallback, never deeper than the layout allows.
    private func candidateURLs(under root: URL, layout: ExternalSaveLayout) -> [URL] {
        for hint in layout.searchHints {
            let directory = hint.split(separator: "/").reduce(root) {
                $0.appendingPathComponent(String($1), isDirectory: true)
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let found = files(under: directory, depth: layout.maxSearchDepth)
            if !found.isEmpty {
                logger.debug("Using hint \(hint), \(found.count) candidates")
                return found
            }
        }
        logger.debug("No hint matched, walking the granted folder")
        return files(under: root, depth: layout.maxSearchDepth)
    }

    private func files(under directory: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [] }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.flatMap { url -> [URL] in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return isDirectory ? files(under: url, depth: depth - 1) : [url]
        }
    }

    /// Empty files are dropped: an emulator that has created a save file but not
    /// written to it yet would otherwise be offered as a save to upload.
    private func candidate(at url: URL) -> ExternalSaveCandidate? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize, size > 0 else { return nil }
        return ExternalSaveCandidate(
            url: url,
            fileName: url.lastPathComponent,
            sizeBytes: size,
            modifiedAt: values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        )
    }
}

/// Why a save could not be written into another app's folder.
enum ExternalSaveWriteError: Error, LocalizedError {
    /// The grant is gone, usually because the bookmark stopped resolving.
    case folderNotGranted
    /// No container directory to keep the replaced file in, so the write is
    /// refused rather than done without a backup.
    case noBackupDirectory

    var errorDescription: String? {
        switch self {
        case .folderNotGranted:
            return String(localized: "The save folder for this app is no longer available. Pick it again in Settings.")
        case .noBackupDirectory:
            return String(localized: "Could not create a backup of the save being replaced, so nothing was written.")
        }
    }
}

private extension DateFormatter {
    /// Sortable and safe in a file name, so spelled out rather than left to
    /// ISO-8601, whose time component carries colons.
    static let backupStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
