import Foundation

final class LocalSaveStoreRepository: PSaveStore {
    private let rootDirectory: URL
    private let fileManager = FileManager.default

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    convenience init() {
        self.init(rootDirectory: SaveStorePaths.defaultRootDirectory())
    }

    // MARK: - Battery

    func readBattery(romId: Int) throws -> Data? {
        let url = SaveStorePaths.batteryURL(root: rootDirectory, romId: romId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func writeBattery(romId: Int, data: Data) throws {
        try ensureDir(romId: romId)
        try data.write(to: SaveStorePaths.batteryURL(root: rootDirectory, romId: romId), options: .atomic)
    }

    func batteryModifiedAt(romId: Int) -> Date? {
        let url = SaveStorePaths.batteryURL(root: rootDirectory, romId: romId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return attrs?.contentModificationDate
    }

    // MARK: - State

    func listStates(romId: Int) throws -> [SaveStateEntry] {
        let dir = SaveStorePaths.statesDir(root: rootDirectory, romId: romId)
        guard fileManager.fileExists(atPath: dir.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return urls.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == SaveStorePaths.stateFileExtension, let slot = Int(name) else { return nil }
            let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return SaveStateEntry(slot: slot, modifiedAt: attrs?.contentModificationDate ?? Date())
        }
    }

    func readState(romId: Int, slot: Int) throws -> Data? {
        let url = SaveStorePaths.stateURL(root: rootDirectory, romId: romId, slot: slot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func writeState(romId: Int, slot: Int, data: Data) throws {
        try ensureDir(romId: romId)
        let dir = SaveStorePaths.statesDir(root: rootDirectory, romId: romId)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: SaveStorePaths.stateURL(root: rootDirectory, romId: romId, slot: slot), options: .atomic)
    }

    func deleteState(romId: Int, slot: Int) throws {
        let url = SaveStorePaths.stateURL(root: rootDirectory, romId: romId, slot: slot)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let thumb = SaveStorePaths.thumbURL(root: rootDirectory, romId: romId, slot: slot)
        if fileManager.fileExists(atPath: thumb.path) {
            try fileManager.removeItem(at: thumb)
        }
    }

    func stateModifiedAt(romId: Int, slot: Int) -> Date? {
        let url = SaveStorePaths.stateURL(root: rootDirectory, romId: romId, slot: slot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return attrs?.contentModificationDate
    }

    // MARK: - Thumbnail

    func readThumbnail(romId: Int, slot: Int) throws -> Data? {
        let url = SaveStorePaths.thumbURL(root: rootDirectory, romId: romId, slot: slot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func writeThumbnail(romId: Int, slot: Int, data: Data) throws {
        try ensureDir(romId: romId)
        try fileManager.createDirectory(
            at: SaveStorePaths.statesDir(root: rootDirectory, romId: romId),
            withIntermediateDirectories: true
        )
        try data.write(to: SaveStorePaths.thumbURL(root: rootDirectory, romId: romId, slot: slot), options: .atomic)
    }

    // MARK: - Undo Save

    func backupSlotForUndoSave(romId: Int, slot: Int) throws {
        try ensureDir(romId: romId)
        try fileManager.createDirectory(
            at: SaveStorePaths.statesDir(root: rootDirectory, romId: romId),
            withIntermediateDirectories: true
        )
        try copyOverwrite(
            from: SaveStorePaths.stateURL(root: rootDirectory, romId: romId, slot: slot),
            to: SaveStorePaths.undoSaveStateURL(root: rootDirectory, romId: romId, slot: slot)
        )
        try copyOverwrite(
            from: SaveStorePaths.thumbURL(root: rootDirectory, romId: romId, slot: slot),
            to: SaveStorePaths.undoSaveThumbURL(root: rootDirectory, romId: romId, slot: slot)
        )
    }

    func restoreSlotFromUndoSave(romId: Int, slot: Int) throws -> Bool {
        let stateSrc = SaveStorePaths.undoSaveStateURL(root: rootDirectory, romId: romId, slot: slot)
        guard fileManager.fileExists(atPath: stateSrc.path) else {
            try deleteState(romId: romId, slot: slot)
            removeIfExists(SaveStorePaths.undoSaveStateURL(root: rootDirectory, romId: romId, slot: slot))
            removeIfExists(SaveStorePaths.undoSaveThumbURL(root: rootDirectory, romId: romId, slot: slot))
            return true
        }
        try copyOverwrite(
            from: stateSrc,
            to: SaveStorePaths.stateURL(root: rootDirectory, romId: romId, slot: slot)
        )
        try copyOverwrite(
            from: SaveStorePaths.undoSaveThumbURL(root: rootDirectory, romId: romId, slot: slot),
            to: SaveStorePaths.thumbURL(root: rootDirectory, romId: romId, slot: slot)
        )
        removeIfExists(stateSrc)
        removeIfExists(SaveStorePaths.undoSaveThumbURL(root: rootDirectory, romId: romId, slot: slot))
        return true
    }

    func hasUndoSave(romId: Int, slot: Int) -> Bool {
        fileManager.fileExists(
            atPath: SaveStorePaths.undoSaveStateURL(root: rootDirectory, romId: romId, slot: slot).path
        )
    }

    // MARK: - Undo Load

    func writeUndoLoadSnapshot(romId: Int, stateData: Data, thumbnailData: Data?) throws {
        try ensureDir(romId: romId)
        try fileManager.createDirectory(
            at: SaveStorePaths.statesDir(root: rootDirectory, romId: romId),
            withIntermediateDirectories: true
        )
        try stateData.write(
            to: SaveStorePaths.undoLoadStateURL(root: rootDirectory, romId: romId),
            options: .atomic
        )
        if let thumbnailData {
            try thumbnailData.write(
                to: SaveStorePaths.undoLoadThumbURL(root: rootDirectory, romId: romId),
                options: .atomic
            )
        } else {
            removeIfExists(SaveStorePaths.undoLoadThumbURL(root: rootDirectory, romId: romId))
        }
    }

    func readUndoLoadState(romId: Int) throws -> Data? {
        let url = SaveStorePaths.undoLoadStateURL(root: rootDirectory, romId: romId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func readUndoLoadThumbnail(romId: Int) throws -> Data? {
        let url = SaveStorePaths.undoLoadThumbURL(root: rootDirectory, romId: romId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func hasUndoLoad(romId: Int) -> Bool {
        fileManager.fileExists(atPath: SaveStorePaths.undoLoadStateURL(root: rootDirectory, romId: romId).path)
    }

    func clearUndoLoad(romId: Int) throws {
        removeIfExists(SaveStorePaths.undoLoadStateURL(root: rootDirectory, romId: romId))
        removeIfExists(SaveStorePaths.undoLoadThumbURL(root: rootDirectory, romId: romId))
    }

    // MARK: - Internal

    private func ensureDir(romId: Int) throws {
        try fileManager.createDirectory(
            at: SaveStorePaths.romDir(root: rootDirectory, romId: romId),
            withIntermediateDirectories: true
        )
    }

    private func copyOverwrite(from src: URL, to dst: URL) throws {
        guard fileManager.fileExists(atPath: src.path) else {
            removeIfExists(dst)
            return
        }
        removeIfExists(dst)
        try fileManager.copyItem(at: src, to: dst)
    }

    private func removeIfExists(_ url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
