import Foundation

final class CloudSaveSyncSettings: ObservableObject {
    static let shared = CloudSaveSyncSettings()

    private let userDefaults = UserDefaults.standard
    private enum Keys {
        static let enabled = "cloud_save_sync_enabled"
        static let lastSyncDatePrefix = "cloud_save_sync_last_date_"
        static let lastSyncTriggerPrefix = "cloud_save_sync_last_trigger_"
    }

    @Published var isEnabled: Bool {
        didSet { userDefaults.set(isEnabled, forKey: Keys.enabled) }
    }

    private init() {
        self.isEnabled = userDefaults.bool(forKey: Keys.enabled)
    }

    // MARK: - Per-ROM sync metadata

    /// Persists the most recent sync for a ROM so the UI can show when and how
    /// it last happened. Called both by the automatic session sync and the
    /// manual sync sheet.
    func recordSync(romId: Int, trigger: SyncTrigger, date: Date = Date()) {
        userDefaults.set(date.timeIntervalSince1970, forKey: Keys.lastSyncDatePrefix + "\(romId)")
        userDefaults.set(trigger.rawValue, forKey: Keys.lastSyncTriggerPrefix + "\(romId)")
    }

    func lastSync(romId: Int) -> SyncMetadata? {
        let dateKey = Keys.lastSyncDatePrefix + "\(romId)"
        guard userDefaults.object(forKey: dateKey) != nil else { return nil }
        let timestamp = userDefaults.double(forKey: dateKey)
        guard timestamp > 0 else { return nil }
        let trigger = SyncTrigger(rawValue: userDefaults.string(forKey: Keys.lastSyncTriggerPrefix + "\(romId)") ?? "") ?? .automatic
        return SyncMetadata(date: Date(timeIntervalSince1970: timestamp), trigger: trigger)
    }
}
