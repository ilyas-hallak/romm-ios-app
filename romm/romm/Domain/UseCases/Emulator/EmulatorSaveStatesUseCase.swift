import Foundation

protocol PEmulatorSaveStatesUseCase {
    // Battery
    func readBattery(romId: Int) throws -> Data?
    func writeBattery(romId: Int, data: Data) throws
    func batteryModifiedAt(romId: Int) -> Date?

    // State
    func listStates(romId: Int) throws -> [SaveStateEntry]
    func readState(romId: Int, slot: Int) throws -> Data?
    func writeState(romId: Int, slot: Int, data: Data) throws
    func deleteState(romId: Int, slot: Int) throws
    func stateModifiedAt(romId: Int, slot: Int) -> Date?

    // Thumbnail
    func readThumbnail(romId: Int, slot: Int) throws -> Data?
    func writeThumbnail(romId: Int, slot: Int, data: Data) throws

    // Undo Save
    func backupSlotForUndoSave(romId: Int, slot: Int) throws
    func restoreSlotFromUndoSave(romId: Int, slot: Int) throws -> Bool
    func hasUndoSave(romId: Int, slot: Int) -> Bool

    // Undo Load
    func writeUndoLoadSnapshot(romId: Int, stateData: Data, thumbnailData: Data?) throws
    func readUndoLoadState(romId: Int) throws -> Data?
    func readUndoLoadThumbnail(romId: Int) throws -> Data?
    func hasUndoLoad(romId: Int) -> Bool
    func clearUndoLoad(romId: Int) throws
}

final class EmulatorSaveStatesUseCase: PEmulatorSaveStatesUseCase {
    private let saveStore: PSaveStore

    init(saveStore: PSaveStore) {
        self.saveStore = saveStore
    }

    func readBattery(romId: Int) throws -> Data? {
        try saveStore.readBattery(romId: romId)
    }
    func writeBattery(romId: Int, data: Data) throws {
        try saveStore.writeBattery(romId: romId, data: data)
    }
    func batteryModifiedAt(romId: Int) -> Date? {
        saveStore.batteryModifiedAt(romId: romId)
    }
    func listStates(romId: Int) throws -> [SaveStateEntry] {
        try saveStore.listStates(romId: romId)
    }
    func readState(romId: Int, slot: Int) throws -> Data? {
        try saveStore.readState(romId: romId, slot: slot)
    }
    func writeState(romId: Int, slot: Int, data: Data) throws {
        try saveStore.writeState(romId: romId, slot: slot, data: data)
    }
    func deleteState(romId: Int, slot: Int) throws {
        try saveStore.deleteState(romId: romId, slot: slot)
    }
    func stateModifiedAt(romId: Int, slot: Int) -> Date? {
        saveStore.stateModifiedAt(romId: romId, slot: slot)
    }
    func readThumbnail(romId: Int, slot: Int) throws -> Data? {
        try saveStore.readThumbnail(romId: romId, slot: slot)
    }
    func writeThumbnail(romId: Int, slot: Int, data: Data) throws {
        try saveStore.writeThumbnail(romId: romId, slot: slot, data: data)
    }
    func backupSlotForUndoSave(romId: Int, slot: Int) throws {
        try saveStore.backupSlotForUndoSave(romId: romId, slot: slot)
    }
    func restoreSlotFromUndoSave(romId: Int, slot: Int) throws -> Bool {
        try saveStore.restoreSlotFromUndoSave(romId: romId, slot: slot)
    }
    func hasUndoSave(romId: Int, slot: Int) -> Bool {
        saveStore.hasUndoSave(romId: romId, slot: slot)
    }
    func writeUndoLoadSnapshot(romId: Int, stateData: Data, thumbnailData: Data?) throws {
        try saveStore.writeUndoLoadSnapshot(romId: romId, stateData: stateData, thumbnailData: thumbnailData)
    }
    func readUndoLoadState(romId: Int) throws -> Data? {
        try saveStore.readUndoLoadState(romId: romId)
    }
    func readUndoLoadThumbnail(romId: Int) throws -> Data? {
        try saveStore.readUndoLoadThumbnail(romId: romId)
    }
    func hasUndoLoad(romId: Int) -> Bool {
        saveStore.hasUndoLoad(romId: romId)
    }
    func clearUndoLoad(romId: Int) throws {
        try saveStore.clearUndoLoad(romId: romId)
    }
}
