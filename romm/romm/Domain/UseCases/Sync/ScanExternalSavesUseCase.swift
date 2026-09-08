import Foundation

/// A battery save found in another app's folder, matched to a ROM here.
struct ExternalSaveFile: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let romId: Int
    let fileName: String
    let sizeBytes: Int
    let modifiedAt: Date
}

/// What one app's folder holds.
struct ExternalSaveScan: Equatable {
    let emulator: ExternalEmulatorID
    let matched: [ExternalSaveFile]
    /// Files that look like saves but belong to no ROM this device knows.
    ///
    /// Counted rather than dropped, because this is the number that says whether
    /// a scan is working: saves found but unmatched means the folder is right and
    /// the matching is wrong, while nothing found at all means the folder or the
    /// path hints are wrong. Those need different fixes.
    let unmatchedFileNames: [String]
    /// True when the granted folder resolved but has moved since.
    let isStale: Bool

    var isEmpty: Bool { matched.isEmpty && unmatchedFileNames.isEmpty }
}

protocol PScanExternalSavesUseCase {
    /// Reads one app's granted folder. Returns nil when no folder was granted.
    func execute(for emulator: ExternalEmulatorID) throws -> ExternalSaveScan?
    /// Reads every app that has a granted folder.
    func executeForAllGranted() -> [ExternalSaveScan]
}

/// Finds the battery saves another emulator app has written.
///
/// Read-only, and deliberately so for now: the entitlement is
/// `user-selected.read-only`, which is enough to offer these saves to the server
/// but not to write anything back.
final class ScanExternalSavesUseCase: PScanExternalSavesUseCase {

    private let logger = Logger.emulator
    private let folderStore: PExternalSaveFolderStore
    private let localROMs: PLocalROMRepository
    private let handoffStore: PExternalEmulatorHandoffStore
    private let fileManager: FileManager

    init(
        folderStore: PExternalSaveFolderStore,
        localROMs: PLocalROMRepository,
        handoffStore: PExternalEmulatorHandoffStore,
        fileManager: FileManager = .default
    ) {
        self.folderStore = folderStore
        self.localROMs = localROMs
        self.handoffStore = handoffStore
        self.fileManager = fileManager
    }

    func execute(for emulator: ExternalEmulatorID) throws -> ExternalSaveScan? {
        guard let layout = emulator.emulator.saveLayout,
              let grant = folderStore.grantedFolder(for: emulator) else { return nil }

        let index = try romIndex(for: emulator, layout: layout)

        return grant.withAccess { root in
            var matched: [ExternalSaveFile] = []
            var unmatched: [String] = []

            for url in candidateFiles(under: root, layout: layout) {
                guard let key = layout.batteryKey(forFileName: url.lastPathComponent) else { continue }
                if let romId = index[key.lowercased()] {
                    if let file = saveFile(at: url, romId: romId) {
                        matched.append(file)
                    }
                } else {
                    unmatched.append(url.lastPathComponent)
                }
            }

            logger.info("Scanned \(emulator.rawValue): \(matched.count) matched, \(unmatched.count) unmatched")
            return ExternalSaveScan(
                emulator: emulator,
                matched: matched,
                unmatchedFileNames: unmatched,
                isStale: grant.isStale
            )
        }
    }

    func executeForAllGranted() -> [ExternalSaveScan] {
        folderStore.grantedEmulators().compactMap { try? execute(for: $0) }
    }

    // MARK: - Private

    /// Maps what a save could be named after back to a ROM id, lowercased so
    /// matching can ignore case without lowercasing on every comparison.
    ///
    /// For an app that names saves after a content hash this only covers ROMs
    /// whose identifier is already known, which in practice means the ones handed
    /// to that app at least once. Hashing the whole library to close that gap
    /// would read every ROM on the device, and a save for a game never opened
    /// over there cannot exist anyway.
    private func romIndex(
        for emulator: ExternalEmulatorID,
        layout: ExternalSaveLayout
    ) throws -> [String: Int] {
        let roms = try localROMs.getAllDownloadedROMs()
        var index: [String: Int] = [:]

        for rom in roms {
            switch layout.naming {
            case .romBaseName:
                // A multi-file ROM has no single name, so every part is offered:
                // the target app named the save after whichever one it opened.
                for file in rom.files {
                    let base = (file.fileName as NSString).deletingPathExtension
                    index[base.lowercased()] = rom.id
                }
            case .gameIdentifier:
                let kind = emulator.emulator.identifierKind
                if let identifier = handoffStore.cachedGameIdentifier(romId: rom.id, kind: kind) {
                    index[identifier.lowercased()] = rom.id
                }
            }
        }
        return index
    }

    /// Files worth looking at, hints first and the whole folder only as a
    /// fallback, never deeper than the layout allows.
    private func candidateFiles(under root: URL, layout: ExternalSaveLayout) -> [URL] {
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

    private func saveFile(at url: URL, romId: Int) -> ExternalSaveFile? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize, size > 0 else { return nil }
        return ExternalSaveFile(
            url: url,
            romId: romId,
            fileName: url.lastPathComponent,
            sizeBytes: size,
            modifiedAt: values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
        )
    }
}
