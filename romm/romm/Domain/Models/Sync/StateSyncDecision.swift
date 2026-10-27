import Foundation

/// Decides what to do about one save-state slot, given what this device has
/// locally, what the server has, and the last baseline both sides agreed on.
///
/// Pure and I/O-free on purpose: both `CloudSaveSyncService` (pre-launch pull)
/// and `SaveSyncRunner` (manual, bidirectional sync) route every slot through
/// this, so the two can never quietly grow different ideas of "changed".
///
/// The server's `updated_at` bumps on *any* row update, not just a content
/// change, so a timestamp compare alone cannot tell a real edit from a row
/// that was merely touched. A baseline (the content hash and row state as of
/// the last successful transfer) is what makes that distinction possible; the
/// two-step shape below exists because telling "row touched, content
/// identical" apart from "content actually changed" needs the server's bytes,
/// which the caller only fetches when actually necessary.
enum StateSyncDecision {
    struct LocalInfo {
        let modifiedAt: Date
        let contentHash: String
    }

    struct ServerInfo {
        let id: Int
        let updatedAt: Date
        let fileName: String
    }

    enum FirstStep: Equatable {
        /// Nothing on either side changed since the baseline.
        case nothing
        case upload
        case download
        /// Both sides have a state, but the server's bytes are needed before
        /// this can be decided: either there is no usable baseline yet
        /// (migration), or the server row was touched and whether its
        /// content actually changed cannot be told without fetching it.
        case needsServerContent
    }

    enum SecondStep: Equatable {
        case nothing
        case upload
        case download
        /// Content is identical on both sides; only the baseline needs
        /// refreshing; nothing has to be transferred.
        case recordBaselineOnly
    }

    static func decideFirstStep(local: LocalInfo?, server: ServerInfo?, baseline: StateSyncBaseline?) -> FirstStep {
        switch (local, server) {
        case (nil, nil):
            return .nothing
        case (nil, .some):
            return .download
        case (.some, nil):
            return .upload
        case (.some(let local), .some(let server)):
            guard let baseline, baseline.serverId == server.id else {
                // No baseline for this row yet (first sync since the feature
                // shipped, or the server row was recreated): cannot tell
                // "changed" from "unchanged" without comparing content.
                return .needsServerContent
            }
            let localChanged = local.contentHash != baseline.contentHash
            let serverRowChanged = server.updatedAt != baseline.serverUpdatedAt
            switch (localChanged, serverRowChanged) {
            case (false, false):
                return .nothing
            case (true, false):
                return .upload
            case (false, true), (true, true):
                // Row touched (content-identical bump, or a real edit) or a
                // genuine two-sided conflict: both need the server's bytes to
                // resolve.
                return .needsServerContent
            }
        }
    }

    static func decideSecondStep(
        local: LocalInfo,
        server: ServerInfo,
        baseline: StateSyncBaseline?,
        serverContentHash: String
    ) -> SecondStep {
        if local.contentHash == serverContentHash {
            return .recordBaselineOnly
        }
        if let baseline, baseline.serverId == server.id {
            let localChanged = local.contentHash != baseline.contentHash
            // Content-based, not `server.updatedAt != baseline.serverUpdatedAt`:
            // the row can be touched (bumping `updated_at`) without its bytes
            // changing, and by this point the bytes are already in hand, so
            // there is no reason to trust the unreliable timestamp instead.
            let serverContentChanged = serverContentHash != baseline.contentHash
            if localChanged && !serverContentChanged {
                return .upload
            }
            if !localChanged && serverContentChanged {
                return .download
            }
            // Both sides' content changed: a genuine conflict, falls through
            // to the timestamp tiebreak below.
        }
        // No usable baseline (migration) or an unresolved two-sided conflict:
        // fall back to the old "newer timestamp wins" rule. The caller
        // records a fresh baseline after this either way.
        if local.modifiedAt > server.updatedAt {
            return .upload
        }
        if server.updatedAt > local.modifiedAt {
            return .download
        }
        return .nothing
    }
}
