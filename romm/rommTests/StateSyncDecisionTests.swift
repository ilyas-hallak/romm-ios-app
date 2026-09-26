import Testing
import Foundation
@testable import romm

/// Every branch of `StateSyncDecision`, the pure table both `CloudSaveSyncService`
/// and `SaveSyncRunner` route their state-slot decisions through. No I/O here:
/// only the inputs a real sync run would have gathered by the time it decides.
struct StateSyncDecisionTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func local(at date: Date, hash: String = "local-hash") -> StateSyncDecision.LocalInfo {
        .init(modifiedAt: date, contentHash: hash)
    }

    private func server(id: Int = 30, at date: Date, fileName: String = "slot0.state") -> StateSyncDecision.ServerInfo {
        .init(id: id, updatedAt: date, fileName: fileName)
    }

    private func baseline(id: Int = 30, at date: Date, hash: String = "local-hash") -> StateSyncBaseline {
        .init(serverId: id, serverUpdatedAt: date, contentHash: hash)
    }

    // MARK: - decideFirstStep

    @Test func neitherSideHasAnythingIsNothing() {
        let step = StateSyncDecision.decideFirstStep(local: nil, server: nil, baseline: nil)
        #expect(step == .nothing)
    }

    @Test func serverOnlyIsDownload() {
        let step = StateSyncDecision.decideFirstStep(local: nil, server: server(at: t0), baseline: nil)
        #expect(step == .download)
    }

    @Test func localOnlyIsUpload() {
        let step = StateSyncDecision.decideFirstStep(local: local(at: t0), server: nil, baseline: nil)
        #expect(step == .upload)
    }

    @Test func bothPresentWithNoBaselineNeedsServerContent() {
        let step = StateSyncDecision.decideFirstStep(local: local(at: t0), server: server(at: t0), baseline: nil)
        #expect(step == .needsServerContent)
    }

    /// A baseline pinned to a server row that no longer exists (the row was
    /// deleted and recreated, or this is a different ROM's leftover baseline)
    /// cannot be trusted: treated the same as no baseline at all.
    @Test func baselinePointingAtADifferentServerRowNeedsServerContent() {
        let stale = baseline(id: 999, at: t0)
        let step = StateSyncDecision.decideFirstStep(local: local(at: t0), server: server(id: 30, at: t0), baseline: stale)
        #expect(step == .needsServerContent)
    }

    @Test func neitherSideChangedSinceBaselineIsNothing() {
        let base = baseline(at: t0, hash: "same-hash")
        let step = StateSyncDecision.decideFirstStep(
            local: local(at: t0, hash: "same-hash"), server: server(at: t0), baseline: base
        )
        #expect(step == .nothing)
    }

    /// Only the local content moved since the baseline: the server row's
    /// timestamp is unreliable (bumped on any row touch), but here it agrees
    /// with the baseline, so there is no ambiguity, upload straight away.
    @Test func onlyLocalChangedSinceBaselineIsUpload() {
        let base = baseline(at: t0, hash: "old-hash")
        let step = StateSyncDecision.decideFirstStep(
            local: local(at: t0, hash: "new-hash"), server: server(at: t0), baseline: base
        )
        #expect(step == .upload)
    }

    /// Only the server row's timestamp moved (a touch with no content
    /// change is exactly the bug this whole mechanism exists for): local
    /// content still matches the baseline, but the row being touched at all
    /// means the actual bytes need comparing before trusting that.
    @Test func onlyServerRowChangedSinceBaselineNeedsServerContent() {
        let base = baseline(at: t0, hash: "same-hash")
        let step = StateSyncDecision.decideFirstStep(
            local: local(at: t0, hash: "same-hash"),
            server: server(at: t0.addingTimeInterval(60)),
            baseline: base
        )
        #expect(step == .needsServerContent)
    }

    @Test func bothSidesChangedSinceBaselineNeedsServerContent() {
        let base = baseline(at: t0, hash: "old-hash")
        let step = StateSyncDecision.decideFirstStep(
            local: local(at: t0, hash: "new-hash"),
            server: server(at: t0.addingTimeInterval(60)),
            baseline: base
        )
        #expect(step == .needsServerContent)
    }

    // MARK: - decideSecondStep

    /// The whole point of the second step: identical bytes mean nothing to
    /// transfer, no matter what the timestamps say.
    @Test func identicalContentRecordsBaselineOnlyRegardlessOfTimestamps() {
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0, hash: "same-hash"),
            server: server(at: t0.addingTimeInterval(999_999)),
            baseline: nil,
            serverContentHash: "same-hash"
        )
        #expect(step == .recordBaselineOnly)
    }

    @Test func noBaselineLocalNewerFallsBackToUpload() {
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0.addingTimeInterval(60), hash: "local-hash"),
            server: server(at: t0),
            baseline: nil,
            serverContentHash: "server-hash"
        )
        #expect(step == .upload)
    }

    @Test func noBaselineServerNewerFallsBackToDownload() {
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0, hash: "local-hash"),
            server: server(at: t0.addingTimeInterval(60)),
            baseline: nil,
            serverContentHash: "server-hash"
        )
        #expect(step == .download)
    }

    @Test func noBaselineEqualTimestampsIsNothing() {
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0, hash: "local-hash"),
            server: server(at: t0),
            baseline: nil,
            serverContentHash: "server-hash"
        )
        #expect(step == .nothing)
    }

    /// The regression case: the server row was merely touched (its
    /// `updated_at` matches the baseline), so despite the server's copy
    /// looking newer than local was at baseline time, local content moved
    /// and the server's did not, local wins.
    @Test func baselineMatchedOnlyLocalChangedIsUpload() {
        let base = baseline(at: t0, hash: "old-hash")
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0, hash: "new-hash"),
            server: server(at: t0),
            baseline: base,
            serverContentHash: "old-hash"
        )
        #expect(step == .upload)
    }

    @Test func baselineMatchedOnlyServerChangedIsDownload() {
        let base = baseline(at: t0, hash: "same-hash")
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0, hash: "same-hash"),
            server: server(at: t0.addingTimeInterval(60)),
            baseline: base,
            serverContentHash: "new-server-hash"
        )
        #expect(step == .download)
    }

    /// Both sides moved since the baseline and the content differs: a real
    /// conflict, resolved the same way a migration (no baseline) is, by
    /// whichever timestamp is newer.
    @Test func baselineMatchedBothChangedFallsBackToTimestamp() {
        let base = baseline(at: t0, hash: "old-hash")
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0.addingTimeInterval(120), hash: "new-local-hash"),
            server: server(at: t0.addingTimeInterval(60)),
            baseline: base,
            serverContentHash: "new-server-hash"
        )
        #expect(step == .upload)
    }

    /// The regression this whole mechanism exists for: the server row was
    /// touched (its `updated_at` moved past the local save's own mtime) but
    /// its actual bytes did not change. A timestamp-only comparison would
    /// wrongly call the server "newer" and downloads over the real local
    /// edit; the content-hash comparison against the baseline must catch
    /// that the server's bytes still match the baseline and keep local.
    @Test func rowTouchedWithUnchangedContentStillUploadsEvenWhenServerTimestampIsNewer() {
        let base = baseline(at: t0, hash: "old-hash")
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0.addingTimeInterval(-60), hash: "new-local-hash"),
            server: server(at: t0.addingTimeInterval(3_600)),
            baseline: base,
            serverContentHash: "old-hash"
        )
        #expect(step == .upload)
    }

    /// A baseline pinned to a different server row is ignored, same as
    /// having none: falls through to the timestamp fallback.
    @Test func baselinePointingAtADifferentServerRowFallsBackToTimestamp() {
        let stale = baseline(id: 999, at: t0, hash: "old-hash")
        let step = StateSyncDecision.decideSecondStep(
            local: local(at: t0, hash: "local-hash"),
            server: server(id: 30, at: t0.addingTimeInterval(60)),
            baseline: stale,
            serverContentHash: "server-hash"
        )
        #expect(step == .download)
    }
}
