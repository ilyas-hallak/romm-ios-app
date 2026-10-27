import Foundation

final class CloudSaveSyncSettings: ObservableObject, PCloudSaveSyncStore, PCloudSaveSyncSettings, PSaveSyncOutcomeStore {
    static let shared = CloudSaveSyncSettings()

    private let userDefaults = UserDefaults.standard
    private enum Keys {
        static let enabled = "cloud_save_sync_enabled"
        static let lastSyncDatePrefix = "cloud_save_sync_last_date_"
        static let lastSyncTriggerPrefix = "cloud_save_sync_last_trigger_"
        static let lastRunDate = "cloud_save_sync_last_run_date"
        static let lastRunUploaded = "cloud_save_sync_last_run_uploaded"
        static let lastRunDownloaded = "cloud_save_sync_last_run_downloaded"
        static let lastRunConflicts = "cloud_save_sync_last_run_conflicts"
        static let lastRunFailed = "cloud_save_sync_last_run_failed"
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

    // MARK: - Last run

    func recordRun(_ outcome: SaveSyncOutcome) {
        userDefaults.set(outcome.date.timeIntervalSince1970, forKey: Keys.lastRunDate)
        userDefaults.set(outcome.uploaded, forKey: Keys.lastRunUploaded)
        userDefaults.set(outcome.downloaded, forKey: Keys.lastRunDownloaded)
        userDefaults.set(outcome.conflicts, forKey: Keys.lastRunConflicts)
        userDefaults.set(outcome.failed, forKey: Keys.lastRunFailed)
    }

    func lastRun() -> SaveSyncOutcome? {
        // Checked for presence rather than for a non-zero date: a run is only
        // absent when nothing ever wrote one, and "no run yet" must not be
        // confused with a run that found nothing to do.
        guard userDefaults.object(forKey: Keys.lastRunDate) != nil else { return nil }
        return SaveSyncOutcome(
            date: Date(timeIntervalSince1970: userDefaults.double(forKey: Keys.lastRunDate)),
            uploaded: userDefaults.integer(forKey: Keys.lastRunUploaded),
            downloaded: userDefaults.integer(forKey: Keys.lastRunDownloaded),
            conflicts: userDefaults.integer(forKey: Keys.lastRunConflicts),
            failed: userDefaults.integer(forKey: Keys.lastRunFailed)
        )
    }
}
