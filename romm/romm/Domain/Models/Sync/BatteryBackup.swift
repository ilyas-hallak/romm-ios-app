import Foundation

/// Which side a conflict-resolution backup came from, named into the file so
/// a later look in Files.app can tell them apart.
enum BatteryBackupOrigin: String {
    case local
    case server
}

/// Pure naming/pruning rules for the conflict-resolution backups kept under
/// `Saves/<romId>/backups/` (see `PSaveStore.backupBattery`), split out so
/// they can be tested without touching the filesystem.
enum BatteryBackupNaming {
    static let keepCount = 10

    static func fileName(at date: Date, origin: BatteryBackupOrigin) -> String {
        "battery-\(iso8601(date))-\(origin.rawValue).sav"
    }

    /// Which of the existing backup file names should be deleted to keep only
    /// the newest `keepCount`. ISO 8601 timestamps sort lexically the same as
    /// chronologically, so a plain string sort is enough to tell newest from
    /// oldest without parsing anything back out of the name.
    static func namesToPrune(existing: [String], keeping keepCount: Int = keepCount) -> [String] {
        guard existing.count > keepCount else { return [] }
        return Array(existing.sorted().prefix(existing.count - keepCount))
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
