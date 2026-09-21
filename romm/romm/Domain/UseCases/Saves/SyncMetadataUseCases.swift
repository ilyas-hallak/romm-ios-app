import Foundation

protocol PRecordSyncUseCase {
    func execute(romId: Int, trigger: SyncTrigger)
}

protocol PGetLastSyncUseCase {
    func execute(romId: Int) -> SyncMetadata?
}

final class RecordSyncUseCase: PRecordSyncUseCase {
    private let store: PCloudSaveSyncStore
    init(store: PCloudSaveSyncStore) { self.store = store }
    func execute(romId: Int, trigger: SyncTrigger) {
        store.recordSync(romId: romId, trigger: trigger, date: Date())
    }
}

final class GetLastSyncUseCase: PGetLastSyncUseCase {
    private let store: PCloudSaveSyncStore
    init(store: PCloudSaveSyncStore) { self.store = store }
    func execute(romId: Int) -> SyncMetadata? {
        store.lastSync(romId: romId)
    }
}

// MARK: - The run as a whole

protocol PRecordSaveSyncRunUseCase {
    func execute(_ outcome: SaveSyncOutcome)
}

protocol PGetLastSaveSyncRunUseCase {
    func execute() -> SaveSyncOutcome?
}

final class RecordSaveSyncRunUseCase: PRecordSaveSyncRunUseCase {
    private let store: PSaveSyncOutcomeStore
    init(store: PSaveSyncOutcomeStore) { self.store = store }
    func execute(_ outcome: SaveSyncOutcome) {
        store.recordRun(outcome)
    }
}

final class GetLastSaveSyncRunUseCase: PGetLastSaveSyncRunUseCase {
    private let store: PSaveSyncOutcomeStore
    init(store: PSaveSyncOutcomeStore) { self.store = store }
    func execute() -> SaveSyncOutcome? {
        store.lastRun()
    }
}
