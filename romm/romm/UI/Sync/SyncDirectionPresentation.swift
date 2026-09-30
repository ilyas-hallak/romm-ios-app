import SwiftUI

/// How a planned direction is drawn and named.
///
/// Shared, so the overview and the plan detail cannot draw the same operation
/// in different colours.
extension SyncPreviewOperation.Direction {
    var icon: String {
        switch self {
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle.fill"
        case .conflict: return "exclamationmark.triangle.fill"
        case .noOp: return "equal.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .upload: return .blue
        case .download: return .green
        case .conflict: return .orange
        case .noOp: return .secondary
        }
    }

    func summary(count: Int) -> String {
        switch self {
        case .upload:
            return count == 1
                ? String(localized: "Upload 1 save")
                : String(localized: "Upload \(count) saves")
        case .download:
            return count == 1
                ? String(localized: "Download 1 save")
                : String(localized: "Download \(count) saves")
        case .conflict:
            return count == 1
                ? String(localized: "1 conflict to resolve")
                : String(localized: "\(count) conflicts to resolve")
        case .noOp:
            return String(localized: "Already in sync")
        }
    }

    /// The short form for a summary row, as in "2 up, 1 down".
    var shortLabel: String {
        switch self {
        case .upload: return String(localized: "up")
        case .download: return String(localized: "down")
        case .conflict: return String(localized: "conflict")
        case .noOp: return String(localized: "in sync")
        }
    }
}

extension SyncPreview {
    /// "2 up, 1 down", the shape a source is listed in on the overview. Nil
    /// when nothing would change, since a row of zeroes reads as pending work.
    var changeSummary: String? {
        guard !isUpToDate else { return nil }
        let counts: [(Int, SyncPreviewOperation.Direction)] = [
            (uploads.count, .upload),
            (downloads.count, .download),
            (conflicts.count, .conflict),
        ]
        return counts
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1.shortLabel)" }
            .joined(separator: ", ")
    }
}

/// How a conflict resolution reads on a menu, shared so the plan detail's row
/// label and its picker cannot end up naming the same choice differently.
extension SyncConflictResolution {
    var label: String {
        switch self {
        case .keepLocal: return String(localized: "Keep this device's save")
        case .takeServer: return String(localized: "Take the server's save")
        case .skip: return String(localized: "Leave both alone")
        }
    }

    /// The form that fits beside a ROM name, as in "Keeping this device's".
    var shortLabel: String {
        switch self {
        case .keepLocal: return String(localized: "Keeping this device's")
        case .takeServer: return String(localized: "Taking the server's")
        case .skip: return String(localized: "Leaving alone")
        }
    }

    var icon: String {
        switch self {
        case .keepLocal: return "arrow.up.circle"
        case .takeServer: return "arrow.down.circle"
        case .skip: return "minus.circle"
        }
    }
}

/// How an apply outcome is drawn in the result list.
extension SyncApplyOutcome.Status {
    var icon: String {
        switch self {
        case .applied: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .applied: return .green
        case .skipped: return .secondary
        case .failed: return .red
        }
    }
}
