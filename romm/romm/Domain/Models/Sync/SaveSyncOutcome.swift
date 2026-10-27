import Foundation

/// What the last completed sync run did, across every ROM.
///
/// Kept so the account badge can say how syncing went without negotiating with
/// the server again. Negotiating is not free and not read-only either: it opens
/// a session server side and cancels the one an open Save Sync screen is
/// holding, so it may only ever happen because the user asked for it.
///
/// Apart from ``SyncMetadata``, which records the same thing per ROM for the
/// ROM rows.
struct SaveSyncOutcome: Equatable {
    let date: Date
    let uploaded: Int
    let downloaded: Int
    /// Saves left behind because both sides had changed.
    let conflicts: Int
    let failed: Int
}
