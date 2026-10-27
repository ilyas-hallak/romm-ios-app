import SwiftUI

/// How saving last went, in the one line the account button and the account
/// sheet have room for.
///
/// The badge sits on the user's own face, so it has to be conservative: it only
/// ever alarms about something that actually happened. Nothing known yet is
/// ``unknown`` and draws no badge at all, rather than a red mark for a sync
/// that was never even attempted.
enum SaveSyncStatus: Equatable {
    /// Cloud save sync is switched off, so there is nothing to report.
    case off
    /// No sync has finished on this device yet, and none has been asked for.
    case unknown
    case checking
    case synced(at: Date?)
    /// A check found saves that would move, worded the way Save Sync words it.
    case pending(summary: String)
    case conflict(count: Int)
    /// The server cannot sync at all, for example because it predates the API.
    case unavailable(reason: String)
    case failed(reason: String)
}

// MARK: - Derivation

extension SaveSyncStatus {
    /// What a finished run leaves behind. Failures outrank conflicts, which
    /// outrank the plain counts: the badge shows the worst thing that happened,
    /// since that is the only part the user may need to act on.
    init(run: SaveSyncOutcome) {
        if run.failed > 0 {
            self = .failed(reason: run.failed == 1
                ? String(localized: "The last sync could not transfer 1 save.")
                : String(localized: "The last sync could not transfer \(run.failed) saves."))
        } else if run.conflicts > 0 {
            self = .conflict(count: run.conflicts)
        } else {
            self = .synced(at: run.date)
        }
    }

    /// What a check found. Conflicts outrank the counts for the same reason.
    init(preview: SyncPreview) {
        if !preview.conflicts.isEmpty {
            self = .conflict(count: preview.conflicts.count)
        } else if let summary = preview.changeSummary {
            self = .pending(summary: summary)
        } else {
            self = .synced(at: nil)
        }
    }

    /// A server that cannot sync is not a failure the user can retry away, so
    /// it reads as unavailable rather than as an error.
    init(error: SyncPreviewError) {
        let reason = error.localizedDescription
        switch error {
        case .notConnected, .serverTooOld, .serverVersionUnknown:
            self = .unavailable(reason: reason)
        case .deviceRegistrationFailed, .negotiationFailed:
            self = .failed(reason: reason)
        }
    }
}

// MARK: - Presentation

extension SaveSyncStatus {
    /// The badge drawn on the account button. Nil for every state that has not
    /// established anything, so an untouched app shows a plain avatar.
    var badgeIcon: String? {
        switch self {
        case .off, .unknown, .checking: return nil
        case .synced: return "checkmark.circle.fill"
        case .pending: return "arrow.triangle.2.circlepath.circle.fill"
        case .conflict: return "exclamationmark.circle.fill"
        case .unavailable: return "minus.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .off, .unknown, .checking, .unavailable: return .secondary
        case .synced: return .green
        case .pending: return .blue
        case .conflict: return .orange
        case .failed: return .red
        }
    }

    /// The trailing text on the Save Sync row.
    var detail: String {
        switch self {
        case .off: return String(localized: "Off")
        case .unknown: return String(localized: "Not checked yet")
        case .checking: return String(localized: "Checking…")
        case .synced(let date):
            guard let date else { return String(localized: "Up to date") }
            return String(localized: "Synced \(date.formatted(.relative(presentation: .named)))")
        case .pending(let summary): return summary
        case .conflict(let count):
            return count == 1
                ? String(localized: "1 conflict")
                : String(localized: "\(count) conflicts")
        case .unavailable: return String(localized: "Unavailable")
        case .failed: return String(localized: "Failed")
        }
    }

    /// The longer wording underneath the row, where the short detail leaves the
    /// user guessing. Nil when the detail already says it all.
    var explanation: String? {
        switch self {
        case .unknown:
            return String(localized: "Nothing has been synced on this device yet. Check now to see where your saves stand.")
        case .unavailable(let reason), .failed(let reason):
            return reason
        default:
            return nil
        }
    }

    /// Accessibility wording for the badge, which is a colour and a glyph and
    /// says nothing on its own.
    var accessibilityDescription: String {
        String(localized: "Save sync: \(detail)")
    }
}
