import Foundation

protocol PGetLocalDataSummaryUseCase {
    func execute() throws -> LocalDataSummary
}

/// Counts the downloaded ROMs and the games whose saves may not be on the
/// server yet.
///
/// "Unsynced" is judged from local bookkeeping only, without asking the
/// server, so it errs on the side of reporting a save: a battery save written
/// after the last recorded sync, and a state slot with no baseline or with
/// content that moved away from it.
final class GetLocalDataSummaryUseCase: PGetLocalDataSummaryUseCase {
    private let localROMRepository: PLocalROMRepository
    private let saveStore: PSaveStore
    private let syncStore: PCloudSaveSyncStore

    init(localROMRepository: PLocalROMRepository, saveStore: PSaveStore, syncStore: PCloudSaveSyncStore) {
        self.localROMRepository = localROMRepository
        self.saveStore = saveStore
        self.syncStore = syncStore
    }

    func execute() throws -> LocalDataSummary {
        let roms = try localROMRepository.getAllDownloadedROMs()
        let unsynced = try saveStore.listRomIds().filter(hasUnsyncedSaves)
        return LocalDataSummary(
            downloadedROMCount: roms.count,
            downloadedBytes: roms.reduce(0) { $0 + $1.totalSizeBytes },
            gamesWithUnsyncedSaves: unsynced.count
        )
    }

    private func hasUnsyncedSaves(romId: Int) throws -> Bool {
        try hasUnsyncedBattery(romId: romId) || hasUnsyncedState(romId: romId)
    }

    private func hasUnsyncedBattery(romId: Int) throws -> Bool {
        guard try saveStore.readBattery(romId: romId) != nil else { return false }
        guard let modifiedAt = saveStore.batteryModifiedAt(romId: romId),
              let lastSync = syncStore.lastSync(romId: romId) else { return true }
        return modifiedAt > lastSync.date
    }

    private func hasUnsyncedState(romId: Int) throws -> Bool {
        try saveStore.listStates(romId: romId).contains { entry in
            guard let baseline = try saveStore.readStateBaseline(romId: romId, slot: entry.slot),
                  let data = try saveStore.readState(romId: romId, slot: entry.slot) else { return true }
            return SaveContentHash.of(data) != baseline.contentHash
        }
    }
}
