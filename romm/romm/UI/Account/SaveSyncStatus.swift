import SwiftUI

/// How the last save sync went, in the one line the account button and the
/// account sheet have room for.
///
/// Derived from the plan the server answers with, so it says what a sync would
/// do rather than what the app believes it did. That is the question after a
/// game came back from RetroArch, Delta or Manic EMU: was the state taken up.
enum SaveSyncStatus: Equatable {
    /// Cloud save sync is switched off, so there is nothing to report.
    case off
    case checking
    case synced
    /// Saves would move, worded the way the Save Sync screen words it.
    case pending(summary: String)
    case conflict(count: Int)
    /// The server cannot sync at all, for example because it predates the API.
    case unavailable(reason: String)
    case failed(reason: String)
}

// MARK: - Derivation

extension SaveSyncStatus {
    /// Conflicts win over the plain counts: a save neither side can claim is
    /// the one thing here the user has to act on.
    init(preview: SyncPreview) {
        if !preview.conflicts.isEmpty {
            self = .conflict(count: preview.conflicts.count)
        } else if let summary = preview.changeSummary {
            self = .pending(summary: summary)
        } else {
            self = .synced
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
    /// The badge drawn on the account button, or nil while there is nothing
    /// worth putting there.
    var badgeIcon: String? {
        switch self {
        case .off, .checking: return nil
        case .synced: return "checkmark.circle.fill"
        case .pending: return "arrow.triangle.2.circlepath.circle.fill"
        case .conflict: return "exclamationmark.circle.fill"
        case .unavailable: return "minus.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .off, .checking, .unavailable: return .secondary
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
        case .checking: return String(localized: "Checking…")
        case .synced: return String(localized: "Up to date")
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
        case .unavailable(let reason), .failed(let reason): return reason
        default: return nil
        }
    }

    /// Accessibility wording for the badge, which is a colour and a glyph and
    /// says nothing on its own.
    var accessibilityDescription: String {
        String(localized: "Save sync: \(detail)")
    }
}
