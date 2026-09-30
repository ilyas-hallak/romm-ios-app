import Foundation

/// Which side of a conflict the user chose to keep.
///
/// A conflict means both sides changed since the last sync, so there is no
/// answer to work out: one of the two saves is going to be replaced and only
/// the user knows which one is worth less. Nothing is applied without a choice
/// recorded here.
enum SyncConflictResolution: Hashable, CaseIterable {
    /// Push this device's save over the server's.
    case keepLocal
    /// Pull the server's save over this device's.
    case takeServer
    /// Leave both sides as they are. The conflict comes back next sync.
    case skip
}

/// What applying a plan did, one entry per operation it was handed.
///
/// Every operation is accounted for, including the ones that were left alone:
/// a save that quietly did not sync is the failure mode worth reporting, so
/// skips carry their reason rather than being dropped from the report.
struct SyncApplyReport {
    let outcomes: [SyncApplyOutcome]
    /// False when the server would not accept the session as closed. The saves
    /// still moved; only the server's bookkeeping is off.
    let sessionClosed: Bool

    var applied: [SyncApplyOutcome] { outcomes.filter { $0.status == .applied } }
    var failures: [SyncApplyOutcome] { outcomes.filter { $0.status.isFailure } }
    var skips: [SyncApplyOutcome] { outcomes.filter { $0.status.isSkip } }
}

/// One operation's fate.
struct SyncApplyOutcome: Identifiable {
    /// Named `Status` rather than `Result` so it cannot be read as Swift's own
    /// `Result` at a call site.
    enum Status: Equatable {
        case applied
        /// Deliberately not carried out, for a reason the report can state.
        case skipped(SyncSkipReason)
        /// Attempted and refused, carrying whatever the failure said.
        case failed(String)

        var isFailure: Bool { if case .failed = self { return true } else { return false } }
        var isSkip: Bool { if case .skipped = self { return true } else { return false } }
    }

    var id: UUID { operation.id }
    let operation: SyncPreviewOperation
    let status: Status
}

/// Why an operation in the plan was not carried out.
///
/// Each case is a situation the plan did not account for, found only once the
/// apply step went looking for the actual file. Reported rather than treated as
/// an error: the rest of the plan is still worth applying.
enum SyncSkipReason: Equatable {
    /// The slot belongs to no save source this build knows, so there is nowhere
    /// to put the save. A save another device filed under a newer app's slot.
    case unknownSource
    /// A conflict the user has not decided yet.
    case conflictNotResolved
    /// A conflict the user chose to leave alone. Told apart from the undecided
    /// case so the report does not read as a prompt the user already answered.
    case conflictSkipped
    /// The local save is gone or unreadable since the preview was taken.
    case localSaveUnavailable
    /// The local save changed since it was reported, so uploading it would send
    /// something the server never planned for. Left for the next sync, which
    /// reports the file as it now is.
    case localSaveChanged
    /// The server side of the operation has no save id, which a download needs.
    case noServerSave
    /// No ROM on this device matches the save, so its name in the other app's
    /// folder cannot be worked out.
    case romNotAvailable
    /// The name the save carries inside the other app cannot be worked out,
    /// which for an app that names saves after a game identifier means the ROM
    /// was never handed to it.
    case saveNameUnknown
    /// The other app's folder holds no save to model a path on, so writing
    /// would mean guessing a path inside someone else's folder.
    case noWritableDestination

    var explanation: String {
        switch self {
        case .unknownSource:
            return String(localized: "This save belongs to an app this version does not know.")
        case .conflictNotResolved:
            return String(localized: "Left alone because no side was chosen.")
        case .conflictSkipped:
            return String(localized: "Left alone, as you asked.")
        case .localSaveUnavailable:
            return String(localized: "The save on this device could not be read.")
        case .localSaveChanged:
            return String(localized: "The save changed while syncing. It will sync next time.")
        case .noServerSave:
            return String(localized: "The server did not name a save to download.")
        case .romNotAvailable:
            return String(localized: "The game for this save is not on this device.")
        case .saveNameUnknown:
            return String(localized: "Could not work out what this save is called in that app.")
        case .noWritableDestination:
            return String(localized: "There is no save in the app's folder to work out where this one goes.")
        }
    }
}
