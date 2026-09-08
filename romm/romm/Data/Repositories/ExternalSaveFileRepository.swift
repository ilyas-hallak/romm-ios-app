import Foundation

/// Walks the folders the user granted for other emulator apps and reports the
/// files worth matching against this device's ROMs.
final class ExternalSaveFileRepository: PExternalSaveFileRepository {

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

    // MARK: - Private

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
