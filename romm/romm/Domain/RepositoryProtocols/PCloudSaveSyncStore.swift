import Foundation

protocol PCloudSaveSyncStore {
    func recordSync(romId: Int, trigger: SyncTrigger, date: Date)
    func lastSync(romId: Int) -> SyncMetadata?
}
