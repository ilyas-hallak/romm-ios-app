import Foundation

/// What a sync would do, worked out without doing any of it.
///
/// Overwriting a save is close to unrepairable, so syncing shows this first.
struct SyncPreview {
    /// This app's registered device on the server.
    let deviceId: String
    /// The session negotiation opened. Every plan belongs to one, and the
    /// server keeps it open until the outcome is reported back.
    let sessionId: Int?
    /// How many saves this device reported, all sources together.
    let reportedSaveCount: Int
    /// The same count split by where the saves live, so the report can name a
    /// source rather than lumping another app's saves in with this device's.
    let reportedCountsBySource: [SyncSaveSource: Int]
    /// Every operation the server planned, ours and other devices' alike.
    let operations: [SyncPreviewOperation]

    var uploads: [SyncPreviewOperation] { operations.filter { $0.direction == .upload } }
    var downloads: [SyncPreviewOperation] { operations.filter { $0.direction == .download } }
    var conflicts: [SyncPreviewOperation] { operations.filter { $0.direction == .conflict } }

    /// True when server and device already agree and syncing would do nothing.
    var isUpToDate: Bool { uploads.isEmpty && downloads.isEmpty && conflicts.isEmpty }

    /// The operations a sync can carry out on its own, conflicts excluded:
    /// those need the user to say which side wins.
    var applicableOperations: [SyncPreviewOperation] { uploads + downloads }
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
    /// The server-side save this operation is about, which downloading it and
    /// replacing it both address. Nil for an upload, where none exists yet.
    let saveId: Int?
    /// The server's name for the file, which is not the local one: a slotted
    /// save carries a datetime tag the server applies on upload.
    let serverFileName: String?
    let slot: String?
    let emulator: String?
    /// The server's own wording, shown as-is so a surprising plan can be traced
    /// back to it.
    let reason: String?
    let serverUpdatedAt: Date?
    /// Which of this device's save sources the slot belongs to, or nil for a
    /// slot this build does not own: a save another device filed under a slot
    /// this version knows nothing about.
    let source: SyncSaveSource?
    /// The file behind a save that lives in another app's folder, as the
    /// preview found it. Nil for the internal store, which is addressed by ROM
    /// id, and for a save this device does not have yet.
    let externalFile: ExternalSaveFile?
    /// When the local save was last written, as reported to the server. Nil
    /// when this device had no save for the pair.
    ///
    /// Kept so a download can tell whether the file it is about to replace is
    /// still the one the plan was made for. An emulator app writing a save
    /// between preview and apply would otherwise lose it without a word.
    let localUpdatedAt: Date?

    init(
        romId: Int,
        direction: Direction,
        saveId: Int? = nil,
        serverFileName: String?,
        slot: String?,
        emulator: String?,
        reason: String?,
        serverUpdatedAt: Date?,
        source: SyncSaveSource? = nil,
        externalFile: ExternalSaveFile? = nil,
        localUpdatedAt: Date? = nil
    ) {
        self.romId = romId
        self.direction = direction
        self.saveId = saveId
        self.serverFileName = serverFileName
        self.slot = slot
        self.emulator = emulator
        self.reason = reason
        self.serverUpdatedAt = serverUpdatedAt
        self.source = source
        self.externalFile = externalFile
        self.localUpdatedAt = localUpdatedAt
    }

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
    case serverTooOld(version: String)
    /// The version could not be established. Apart from `serverTooOld`, which
    /// is a verdict: this one asks the user to reconnect.
    case serverVersionUnknown
    /// Registration was refused, so there is no device to negotiate for.
    case deviceRegistrationFailed
    /// Negotiation itself failed.
    case negotiationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return String(localized: "Connect to a RomM server to sync saves.")
        case .serverTooOld(let version):
            return String(localized: "This server runs RomM \(version), which is too old to sync saves. RomM 4.9 or newer is required.")
        case .serverVersionUnknown:
            return String(localized: "Could not tell which RomM version this server runs. Reconnect to it and try again.")
        case .deviceRegistrationFailed:
            return String(localized: "This device could not be registered with the server.")
        case .negotiationFailed(let message):
            return message
        }
    }
}
