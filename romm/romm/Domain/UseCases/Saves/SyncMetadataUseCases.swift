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
