import Foundation

/// What this device last agreed with the server about one save-state slot.
///
/// Recorded only after a successful upload or download. A push that never
/// reached the server (offline, killed app, a 403) leaves this stale on
/// purpose: the next sync then sees "local changed since the baseline" and
/// retries, instead of losing newer local content to a server row whose
/// `updated_at` moved for a reason that has nothing to do with its content
/// (the server bumps it on every row update, not just content changes).
struct StateSyncBaseline: Codable, Equatable {
    let serverId: Int
    let serverUpdatedAt: Date
    let contentHash: String
}
