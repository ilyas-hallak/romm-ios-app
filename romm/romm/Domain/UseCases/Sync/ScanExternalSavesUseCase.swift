import Foundation

protocol PScanExternalSavesUseCase {
    /// Reads one app's granted folder. Returns nil when no folder was granted.
    func execute(for emulator: ExternalEmulatorID) throws -> ExternalSaveScan?
    /// Reads every app that has a granted folder.
    func executeForAllGranted() -> [ExternalSaveScan]
}

/// Matches the battery saves another emulator app has written to the ROMs this
/// device has downloaded.
///
/// Only the matching lives here. Finding the files is
/// `PExternalSaveFileRepository`'s job, which keeps bookmarks, security scopes
/// and directory walks out of the domain.
final class ScanExternalSavesUseCase: PScanExternalSavesUseCase {

    private let logger = Logger.emulator
    private let saveFiles: PExternalSaveFileRepository
    private let localROMs: PLocalROMRepository
    private let handoffStore: PExternalEmulatorHandoffStore

    init(
        saveFiles: PExternalSaveFileRepository,
        localROMs: PLocalROMRepository,
        handoffStore: PExternalEmulatorHandoffStore
    ) {
        self.saveFiles = saveFiles
        self.localROMs = localROMs
        self.handoffStore = handoffStore
    }

    func execute(for emulator: ExternalEmulatorID) throws -> ExternalSaveScan? {
        guard let layout = emulator.emulator.saveLayout,
              let contents = saveFiles.contents(for: emulator) else { return nil }

        let index = try romIndex(for: emulator, layout: layout)
        var matched: [ExternalSaveFile] = []
        var unmatched: [String] = []

        for candidate in contents.candidates {
            guard let key = layout.batteryKey(forFileName: candidate.fileName) else { continue }
            if let romId = index[key.lowercased()] {
                matched.append(ExternalSaveFile(candidate: candidate, romId: romId))
            } else {
                unmatched.append(candidate.fileName)
            }
        }

        logger.info("Scanned \(emulator.rawValue): \(matched.count) matched, \(unmatched.count) unmatched")
        return ExternalSaveScan(
            emulator: emulator,
            matched: matched,
            unmatchedFileNames: unmatched,
            isStale: contents.isStale
        )
    }

    func executeForAllGranted() -> [ExternalSaveScan] {
        saveFiles.emulatorsWithFolder().compactMap { try? execute(for: $0) }
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
}
