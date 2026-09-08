import SwiftUI

/// How a planned direction is drawn and named.
///
/// Shared rather than file-private, because the overview and the plan detail
/// have to agree: the same operation must not be blue in one place and green in
/// the other.
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
    /// "2 up, 1 down", the shape a source is listed in on the overview.
    ///
    /// Nil when a sync would change nothing: a row of zeroes reads as work the
    /// sync is about to do.
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
