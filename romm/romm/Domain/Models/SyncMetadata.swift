import Foundation

/// How a sync was triggered: automatically by the app (on launch / after a
/// local save) or manually by the user via the sync sheet.
enum SyncTrigger: String {
    case automatic
    case manual
}

/// Lightweight record of the most recent sync for a single ROM.
struct SyncMetadata: Equatable {
    let date: Date
    let trigger: SyncTrigger
}
