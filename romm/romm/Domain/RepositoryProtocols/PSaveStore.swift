import Foundation

protocol PSaveStore {
    /// Every ROM this store holds something for.
    ///
    /// Sync negotiation is server-wide rather than per ROM, so a caller has to
    /// be able to report the whole local library in one request; every other
    /// read here needs a ROM id it does not yet know.
    func listRomIds() throws -> [Int]

    func readBattery(romId: Int) throws -> Data?
    func writeBattery(romId: Int, data: Data) throws
    func batteryModifiedAt(romId: Int) -> Date?
    func setBatteryModifiedAt(romId: Int, date: Date) throws

    func listStates(romId: Int) throws -> [SaveStateEntry]
    func readState(romId: Int, slot: Int) throws -> Data?
    func writeState(romId: Int, slot: Int, data: Data) throws
    func deleteState(romId: Int, slot: Int) throws
    func stateModifiedAt(romId: Int, slot: Int) -> Date?
    func setStateModifiedAt(romId: Int, slot: Int, date: Date) throws

    func readThumbnail(romId: Int, slot: Int) throws -> Data?
    func writeThumbnail(romId: Int, slot: Int, data: Data) throws

    // Undo Save: snapshot existing slot before overwrite
    func backupSlotForUndoSave(romId: Int, slot: Int) throws
    func restoreSlotFromUndoSave(romId: Int, slot: Int) throws -> Bool
    func hasUndoSave(romId: Int, slot: Int) -> Bool

    // Undo Load: snapshot running emulator before loading another slot
    func writeUndoLoadSnapshot(romId: Int, stateData: Data, thumbnailData: Data?) throws
    func readUndoLoadState(romId: Int) throws -> Data?
    func readUndoLoadThumbnail(romId: Int) throws -> Data?
    func hasUndoLoad(romId: Int) -> Bool
    func clearUndoLoad(romId: Int) throws
}
