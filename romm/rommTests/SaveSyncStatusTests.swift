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

struct SaveSyncStatusTests {

    @Test func aPlanWithNothingToDoReadsAsSynced() {
        #expect(SaveSyncStatus(preview: preview([])) == .synced)
    }

    @Test func aPlanThatMovesSavesReportsTheSameSummaryTheSyncScreenShows() {
        let plan = preview([
            operation(.upload, romId: 1),
            operation(.upload, romId: 2),
            operation(.download, romId: 3),
        ])

        #expect(SaveSyncStatus(preview: plan) == .pending(summary: plan.changeSummary ?? ""))
    }

    /// A save neither side can claim is the one thing here the user has to act
    /// on, so it outranks the counts it would otherwise be buried in.
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
        #expect(SaveSyncStatus(preview: preview([operation(.noOp, romId: 1)])) == .synced)
    }

    @Test func aServerThatCannotSyncReadsAsUnavailableRatherThanFailed() {
        let tooOld = SaveSyncStatus(error: .serverTooOld(version: "4.8.1"))
        let unknown = SaveSyncStatus(error: .serverVersionUnknown)

        #expect(tooOld == .unavailable(reason: SyncPreviewError.serverTooOld(version: "4.8.1").localizedDescription))
        #expect(unknown == .unavailable(reason: SyncPreviewError.serverVersionUnknown.localizedDescription))
        #expect(tooOld.detail == String(localized: "Unavailable"))
    }

    @Test func aRefusedOrBrokenNegotiationReadsAsFailed() {
        #expect(SaveSyncStatus(error: .deviceRegistrationFailed) == .failed(
            reason: SyncPreviewError.deviceRegistrationFailed.localizedDescription
        ))
        #expect(SaveSyncStatus(error: .negotiationFailed("timeout")) == .failed(reason: "timeout"))
    }

    /// The badge is a colour and a glyph, so a state that has nothing to say
    /// must not draw one at all.
    @Test func onlyStatesWithSomethingToSayCarryABadge() {
        #expect(SaveSyncStatus.off.badgeIcon == nil)
        #expect(SaveSyncStatus.checking.badgeIcon == nil)
        #expect(SaveSyncStatus.synced.badgeIcon != nil)
        #expect(SaveSyncStatus.conflict(count: 1).badgeIcon != nil)
    }

    /// Only the states whose short detail leaves the user guessing get the
    /// longer wording underneath.
    @Test func onlyTheOpaqueStatesExplainThemselves() {
        #expect(SaveSyncStatus.synced.explanation == nil)
        #expect(SaveSyncStatus.pending(summary: "1 up").explanation == nil)
        #expect(SaveSyncStatus.failed(reason: "timeout").explanation == "timeout")
    }
}
