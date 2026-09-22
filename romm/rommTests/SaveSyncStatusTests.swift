//
//  SaveSyncStatusTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

private func operation(_ direction: SyncPreviewOperation.Direction, romId: Int) -> SyncPreviewOperation {
    SyncPreviewOperation(
        romId: romId,
        direction: direction,
        serverFileName: nil,
        slot: SaveSlot.battery,
        emulator: nil,
        reason: nil,
        serverUpdatedAt: nil
    )
}

private func preview(_ operations: [SyncPreviewOperation]) -> SyncPreview {
    SyncPreview(deviceId: "d1", reportedSaveCount: operations.count, operations: operations)
}

private func run(uploaded: Int = 0, downloaded: Int = 0, conflicts: Int = 0, failed: Int = 0) -> SaveSyncOutcome {
    SaveSyncOutcome(
        date: Date(timeIntervalSince1970: 1_700_000_000),
        uploaded: uploaded,
        downloaded: downloaded,
        conflicts: conflicts,
        failed: failed
    )
}

struct SaveSyncStatusTests {

    // MARK: - What a finished run left behind

    @Test func aCleanRunReadsAsSyncedAtItsOwnTime() {
        let outcome = run(uploaded: 3, downloaded: 1)

        #expect(SaveSyncStatus(run: outcome) == .synced(at: outcome.date))
    }

    /// The badge shows the worst thing that happened, since that is the only
    /// part the user may have to act on.
    @Test func aRunReportsItsWorstResultFirst() {
        #expect(SaveSyncStatus(run: run(uploaded: 2, conflicts: 1, failed: 1)).badgeIcon
            == SaveSyncStatus.failed(reason: "").badgeIcon)
        #expect(SaveSyncStatus(run: run(uploaded: 2, conflicts: 3)) == .conflict(count: 3))
    }

    // MARK: - What a check found

    @Test func aPlanWithNothingToDoReadsAsSynced() {
        #expect(SaveSyncStatus(preview: preview([])) == .synced(at: nil))
    }

    @Test func aPlanThatMovesSavesReportsTheSameSummaryTheSyncScreenShows() {
        let plan = preview([
            operation(.upload, romId: 1),
            operation(.upload, romId: 2),
            operation(.download, romId: 3),
        ])

        #expect(SaveSyncStatus(preview: plan) == .pending(summary: "2 up, 1 down"))
    }

    @Test func conflictsOutrankTheCounts() {
        let plan = preview([
            operation(.upload, romId: 1),
            operation(.conflict, romId: 2),
            operation(.conflict, romId: 3),
        ])

        #expect(SaveSyncStatus(preview: plan) == .conflict(count: 2))
    }

    /// A no-op is the server saying both sides already agree, which is exactly
    /// "up to date" and must not read as pending work.
    @Test func noOpsDoNotCountAsPendingWork() {
        #expect(SaveSyncStatus(preview: preview([operation(.noOp, romId: 1)])) == .synced(at: nil))
    }

    // MARK: - Failures

    @Test func aServerThatCannotSyncReadsAsUnavailableRatherThanFailed() {
        let tooOld = SaveSyncStatus(error: .serverTooOld(version: "4.8.1"))

        #expect(tooOld == .unavailable(reason: SyncPreviewError.serverTooOld(version: "4.8.1").localizedDescription))
        #expect(SaveSyncStatus(error: .serverVersionUnknown).badgeIcon == "minus.circle.fill")
        #expect(tooOld.tint != .red)
    }

    @Test func aRefusedOrBrokenNegotiationReadsAsFailed() {
        #expect(SaveSyncStatus(error: .deviceRegistrationFailed) == .failed(
            reason: SyncPreviewError.deviceRegistrationFailed.localizedDescription
        ))
        #expect(SaveSyncStatus(error: .negotiationFailed("timeout")) == .failed(reason: "timeout"))
    }

    // MARK: - What the badge is allowed to claim

    /// The badge sits on the user's own face, so a state that has established
    /// nothing must draw nothing at all. A red mark for a sync that was never
    /// attempted is the one thing this must never do.
    @Test func onlyAnEstablishedStateCarriesABadge() {
        #expect(SaveSyncStatus.off.badgeIcon == nil)
        #expect(SaveSyncStatus.unknown.badgeIcon == nil)
        #expect(SaveSyncStatus.checking.badgeIcon == nil)
        #expect(SaveSyncStatus.synced(at: nil).badgeIcon != nil)
        #expect(SaveSyncStatus.conflict(count: 1).badgeIcon != nil)
    }

    /// Red is reserved for a sync that actually ran and did not work.
    @Test func onlyARealFailureIsRed() {
        let red: [SaveSyncStatus] = [.failed(reason: "boom")]
        let notRed: [SaveSyncStatus] = [
            .off, .unknown, .checking, .synced(at: nil),
            .pending(summary: "1 up"), .conflict(count: 1), .unavailable(reason: "old"),
        ]

        #expect(red.allSatisfy { $0.tint == .red })
        #expect(notRed.allSatisfy { $0.tint != .red })
    }

    /// Unknown is where the user is offered a check, so it has to say so.
    @Test func theOpaqueStatesExplainThemselves() {
        #expect(SaveSyncStatus.unknown.explanation != nil)
        #expect(SaveSyncStatus.failed(reason: "timeout").explanation == "timeout")
        #expect(SaveSyncStatus.synced(at: nil).explanation == nil)
        #expect(SaveSyncStatus.pending(summary: "1 up").explanation == nil)
    }
}
