import Foundation
@testable import romm

/// Minimal `PSaveStore` double: unlike `LocalSaveStoreRepository`, it can
/// report a battery file that exists with no modification date attached,
/// which the filesystem-backed store cannot be made to do.
final class FakeSaveStore: PSaveStore, @unchecked Sendable {
    var romIds: [Int] = []
    var batteryData: [Int: Data] = [:]
    var batteryModifiedAtByRomId: [Int: Date] = [:]

    func listRomIds() throws -> [Int] { romIds }
    func deleteSaves(romId: Int) throws {
        romIds.removeAll { $0 == romId }
        batteryData[romId] = nil
        batteryModifiedAtByRomId[romId] = nil
    }
    func readBattery(romId: Int) throws -> Data? { batteryData[romId] }
    func writeBattery(romId: Int, data: Data) throws { batteryData[romId] = data }
    func batteryModifiedAt(romId: Int) -> Date? { batteryModifiedAtByRomId[romId] }
    func setBatteryModifiedAt(romId: Int, date: Date) throws { batteryModifiedAtByRomId[romId] = date }
    func backupBattery(romId: Int, data: Data, origin: BatteryBackupOrigin) throws {}

    func listStates(romId: Int) throws -> [SaveStateEntry] { [] }
    func readState(romId: Int, slot: Int) throws -> Data? { nil }
    func writeState(romId: Int, slot: Int, data: Data) throws {}
    func deleteState(romId: Int, slot: Int) throws {}
    func stateModifiedAt(romId: Int, slot: Int) -> Date? { nil }
    func setStateModifiedAt(romId: Int, slot: Int, date: Date) throws {}

    func readThumbnail(romId: Int, slot: Int) throws -> Data? { nil }
    func writeThumbnail(romId: Int, slot: Int, data: Data) throws {}
    func deleteThumbnail(romId: Int, slot: Int) throws {}

    func readStateBaseline(romId: Int, slot: Int) throws -> StateSyncBaseline? { nil }
    func writeStateBaseline(romId: Int, slot: Int, baseline: StateSyncBaseline) throws {}

    func backupSlotForUndoSave(romId: Int, slot: Int) throws {}
    func restoreSlotFromUndoSave(romId: Int, slot: Int) throws -> Bool { false }
    func hasUndoSave(romId: Int, slot: Int) -> Bool { false }

    func writeUndoLoadSnapshot(romId: Int, stateData: Data, thumbnailData: Data?) throws {}
    func readUndoLoadState(romId: Int) throws -> Data? { nil }
    func readUndoLoadThumbnail(romId: Int) throws -> Data? { nil }
    func hasUndoLoad(romId: Int) -> Bool { false }
    func clearUndoLoad(romId: Int) throws {}
}
