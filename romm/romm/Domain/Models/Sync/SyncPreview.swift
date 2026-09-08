import Foundation

/// What a sync would do, worked out without doing any of it.
///
/// Overwriting a save is close to unrepairable, so syncing shows this first and
/// only acts once the user has agreed to it.
struct SyncPreview {
    /// This app's registered device on the server.
    let deviceId: String
    /// How many battery saves this device reported.
    let reportedSaveCount: Int
    /// Every operation the server planned, ours and other devices' alike.
    let operations: [SyncPreviewOperation]

    var uploads: [SyncPreviewOperation] { operations.filter { $0.direction == .upload } }
    var downloads: [SyncPreviewOperation] { operations.filter { $0.direction == .download } }
    var conflicts: [SyncPreviewOperation] { operations.filter { $0.direction == .conflict } }

    /// True when server and device already agree and syncing would do nothing.
    var isUpToDate: Bool { uploads.isEmpty && downloads.isEmpty && conflicts.isEmpty }
}

/// A single planned change, flattened from the server's operation list.
struct SyncPreviewOperation: Identifiable, Equatable {
    enum Direction: Equatable {
        /// The device holds a save the server does not have, or a newer one.
        case upload
        /// The server holds a save this device does not have, or a newer one.
        case download
        /// Both sides changed since the last sync and neither can be preferred.
        case conflict
        /// Already in agreement.
        case noOp
    }

    let id = UUID()
    let romId: Int
    let direction: Direction
    /// The server's name for the file, which is not the local one: a slotted
    /// save carries a datetime tag the server applies on upload.
    let serverFileName: String?
    let slot: String?
    let emulator: String?
    /// The server's own wording for why it planned this, shown as-is rather
    /// than reworded, so a surprising plan can be traced back to the server.
    let reason: String?
    let serverUpdatedAt: Date?

    static func == (lhs: SyncPreviewOperation, rhs: SyncPreviewOperation) -> Bool {
        lhs.id == rhs.id
    }
}

/// Why a preview could not be produced. Each case is a state the sync screen
/// has to explain rather than a failure to report as an error.
enum SyncPreviewError: Error, LocalizedError, Equatable {
    /// No server configured, or the user is not signed in.
    case notConnected
    /// The server predates the sync API (RomM 4.9).
    case serverTooOld
    /// Registration was refused, so there is no device to negotiate for.
    case deviceRegistrationFailed
    /// Negotiation itself failed.
    case negotiationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return String(localized: "Connect to a RomM server to sync saves.")
        case .serverTooOld:
            return String(localized: "This server is too old to sync saves. RomM 4.9 or newer is required.")
        case .deviceRegistrationFailed:
            return String(localized: "This device could not be registered with the server.")
        case .negotiationFailed(let message):
            return message
        }
    }
}
