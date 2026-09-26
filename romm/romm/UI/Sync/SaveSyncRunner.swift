//
//  SaveSyncRunner.swift
//  romm
//

import Foundation

/// What one manual sync run did.
struct SaveSyncReport: Equatable {
    var uploaded = 0
    var downloaded = 0
    var skippedConflicts = 0
    /// Operations the plan called for that were not carried out because they
    /// no longer applied: a stale plan (the negotiate result covers every
    /// device, and can also outlive a leave-and-return to this screen), no
    /// matching file to act on, or the content was already byte-identical on
    /// both sides (content beats a stale or clock-skewed timestamp). Not
    /// failures, just nothing to do anymore.
    var skipped = 0
    var failed = 0
    var errors: [String] = []
    /// What the run did with each external app's matched saves. Kept apart
    /// from the totals because nothing is ever written back into those
    /// folders, so their rows have no other way to say what happened.
    var externalApps: [ExternalEmulatorID: ExternalAppOutcome] = [:]

    /// One external app's share of a run.
    struct ExternalAppOutcome: Equatable {
        var uploaded = 0
        var failed = 0
        /// Saves the server refused, so they are still only in the app's
        /// folder. Counted apart from failures: nothing went wrong here, the
        /// save just did not make it up.
        var conflicts = 0
    }
}

@MainActor
protocol PSaveSyncRunner {
    /// Runs `preview` (battery uploads/downloads for this device, conflicts
    /// left untouched) and, separately, uploads whatever the external apps'
    /// scans matched. One failure never stops the rest of the run.
    func run(
        preview: SyncPreview,
        externalScans: [ExternalEmulatorID: ExternalSaveScan]
    ) async -> SaveSyncReport
}

/// Executes an already-negotiated `SyncPreview`, plus the external emulator
/// apps' matched saves the preview never covered.
///
/// Lives beside the automatic sync service rather than as a UseCase: it
/// composes several of the Save/State UseCases, and a UseCase may not call
/// another one. Composition belongs here, in a Session-layer service the
/// ViewModel drives.
@MainActor
final class SaveSyncRunner: PSaveSyncRunner {

    private let logger = Logger.sync

    private let saveStore: PSaveStore
    private let uploadSaveUseCase: PUploadSaveUseCase
    private let downloadSaveUseCase: PDownloadSaveUseCase
    private let confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase
    /// Only used by `runExternalUpload`'s freshness gate now: battery upload and
    /// download are resolved from the plan itself (`SyncPreviewOperation`), which
    /// already carries the save id and content hash the server negotiated.
    private let listServerSavesUseCase: PListServerSavesUseCase
    private let completeSyncSessionUseCase: PCompleteSyncSessionUseCase
    private let externalSaveFolderStore: PExternalSaveFolderStore
    private let recordRunUseCase: PRecordSaveSyncRunUseCase
    /// Routes every state slot through the same decision logic
    /// `CloudSaveSyncService` uses, so the two never grow different ideas of
    /// "changed".
    private let stateSyncCoordinator: StateSyncCoordinator

    init(
        saveStore: PSaveStore,
        uploadSaveUseCase: PUploadSaveUseCase,
        downloadSaveUseCase: PDownloadSaveUseCase,
        confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase,
        listServerSavesUseCase: PListServerSavesUseCase,
        listServerStatesUseCase: PListServerStatesUseCase,
        uploadStateUseCase: PUploadStateUseCase,
        updateStateUseCase: PUpdateStateUseCase,
        downloadStateUseCase: PDownloadStateUseCase,
        completeSyncSessionUseCase: PCompleteSyncSessionUseCase,
        externalSaveFolderStore: PExternalSaveFolderStore,
        recordRunUseCase: PRecordSaveSyncRunUseCase
    ) {
        self.saveStore = saveStore
        self.uploadSaveUseCase = uploadSaveUseCase
        self.downloadSaveUseCase = downloadSaveUseCase
        self.confirmSaveDownloadUseCase = confirmSaveDownloadUseCase
        self.listServerSavesUseCase = listServerSavesUseCase
        self.completeSyncSessionUseCase = completeSyncSessionUseCase
        self.externalSaveFolderStore = externalSaveFolderStore
        self.recordRunUseCase = recordRunUseCase
        self.stateSyncCoordinator = StateSyncCoordinator(
            saveStore: saveStore,
            listStatesUseCase: listServerStatesUseCase,
            uploadStateUseCase: uploadStateUseCase,
            updateStateUseCase: updateStateUseCase,
            downloadStateUseCase: downloadStateUseCase
        )
    }

    func run(
        preview: SyncPreview,
        externalScans: [ExternalEmulatorID: ExternalSaveScan]
    ) async -> SaveSyncReport {
        var report = SaveSyncReport()
        report.skippedConflicts = preview.conflicts.count

        // Only the battery upload/download outcomes below actually came from
        // the negotiated plan, so only they are reported back to the session
        // negotiate opened. States (never part of the plan, see
        // SyncPreviewUseCase) and external-app uploads (never negotiated at
        // all) still show up in `report` for the UI, just not in this tally.
        var negotiatedCompleted = 0
        var negotiatedFailed = 0

        for op in preview.uploads {
            let outcome = await runBatteryUpload(op, deviceId: preview.deviceId, sessionId: preview.sessionId)
            apply(outcome, to: &report)
            tally(outcome, completed: &negotiatedCompleted, failed: &negotiatedFailed)
        }
        for op in preview.downloads {
            let outcome = await runBatteryDownload(op, deviceId: preview.deviceId)
            apply(outcome, to: &report)
            tally(outcome, completed: &negotiatedCompleted, failed: &negotiatedFailed)
        }

        // States are not part of the negotiate plan (see SyncPreviewUseCase),
        // so every ROM this device holds anything for is checked slot by slot.
        let romIds = (try? saveStore.listRomIds()) ?? []
        for romId in romIds {
            for outcome in await runStatesSync(romId: romId) {
                apply(outcome, to: &report)
            }
        }

        for (emulator, outcomes) in await runExternalUploads(scans: externalScans, deviceId: preview.deviceId) {
            var perApp = SaveSyncReport.ExternalAppOutcome()
            for outcome in outcomes {
                apply(outcome, to: &report)
                apply(outcome, to: &perApp)
            }
            report.externalApps[emulator] = perApp
        }

        logger.info("Manual sync finished: uploaded=\(report.uploaded) "
            + "downloaded=\(report.downloaded) conflicts=\(report.skippedConflicts) "
            + "skipped=\(report.skipped) failed=\(report.failed)")

        // What the account badge reads. Recorded here because this is the one
        // place a whole run ends with a real result, so the badge never has to
        // negotiate with the server just to have something to show.
        recordRunUseCase.execute(SaveSyncOutcome(
            date: Date(),
            uploaded: report.uploaded,
            downloaded: report.downloaded,
            conflicts: report.skippedConflicts,
            failed: report.failed
        ))

        // Purely the server's own bookkeeping (see CompleteSyncSessionUseCase),
        // and only meaningful when negotiate actually opened a session.
        if let sessionId = preview.sessionId {
            do {
                try await completeSyncSessionUseCase.execute(
                    sessionId: sessionId,
                    operationsCompleted: negotiatedCompleted,
                    operationsFailed: negotiatedFailed
                )
            } catch {
                logger.warning("Could not close sync session \(sessionId): \(error.localizedDescription)")
            }
        }

        return report
    }

    // MARK: - Battery (this device)

    /// Uploads under the battery slot. `preview` lists every device's planned
    /// operations, not just this one's (see `SyncPreview`), so an upload op
    /// is only followed through when this device actually holds a local
    /// battery file whose timestamp is not older than the server state the
    /// operation was computed against; otherwise it would push another
    /// device's stale plan as if it were this device's own newer save.
    ///
    /// Dedup against an existing identical save is the server's job now (a
    /// slotted upload whose content hash matches is discarded server-side and
    /// the existing row handed back, see the sync API spec), so this never
    /// checks content hashes before uploading.
    private func runBatteryUpload(_ op: SyncPreviewOperation, deviceId: String, sessionId: String?) async -> StepOutcome {
        guard let data = try? saveStore.readBattery(romId: op.romId), !data.isEmpty else {
            return .skipped
        }
        if let serverUpdatedAt = op.serverUpdatedAt {
            guard let localMTime = saveStore.batteryModifiedAt(romId: op.romId), localMTime >= serverUpdatedAt else {
                return .skipped
            }
        }

        do {
            // The server stamps its own timestamp onto every slot upload's
            // file name, so the name is pure decoration and never lets a
            // slot upload match an existing row by name. Reusing
            // `op.serverFileName` (itself already stamped) would only grow a
            // second timestamp onto it on every run, so this always uploads
            // under the same fixed name.
            _ = try await uploadSaveUseCase.execute(
                romId: op.romId,
                emulator: nil,
                slot: SaveSlot.battery,
                deviceId: deviceId,
                sessionId: sessionId,
                autocleanup: true,
                // The server planned this upload itself, so it has already
                // decided this device's save wins. Without `overwrite` it would
                // then refuse its own plan with 409 whenever the slot holds a
                // row this device never synced, and since negotiate keeps
                // planning the same upload, the save could never go up at all.
                overwrite: true,
                fileName: "battery.sav",
                fileData: data,
                screenshotData: nil
            )
        } catch APIClientError.conflict {
            // `overwrite` above switches the server's guard off entirely, so
            // this should not happen anymore. Kept so a server that refuses
            // anyway is never reported as a failed upload: the next negotiate
            // plans around whatever state it is in.
            return .conflict
        } catch {
            return .failed("ROM \(op.romId): battery upload failed (\(error.localizedDescription))")
        }
        return .uploaded
    }

    /// Downloads are resolved by the save id the plan already carries
    /// (`op.saveId`), not by matching a file name against a freshly listed
    /// server save: two saves of the same ROM can share a name, and the id
    /// is the only thing that unambiguously names one row.
    private func runBatteryDownload(_ op: SyncPreviewOperation, deviceId: String) async -> StepOutcome {
        guard let saveId = op.saveId else {
            return .skipped
        }

        // Defense in depth: the preview already drops non-battery slots, but
        // this runs off whatever preview it is handed, and a foreign-slot
        // download (e.g. this ROM's "autosave" or "default" row from another
        // client) written here would silently clobber the local battery file.
        if let slot = op.slot, slot != SaveSlot.battery {
            return .skipped
        }

        // Content beats timestamp: a clock-skewed write can make the server
        // copy look newer while it is actually byte-identical to what is
        // already on disk here. Downloading it would just churn the same
        // bytes back and forth. Uses the hash the plan already carries, so
        // this never has to refetch the save just to compare it.
        if let serverContentHash = op.serverContentHash,
           let localData = try? saveStore.readBattery(romId: op.romId),
           SaveContentHash.of(localData) == serverContentHash {
            return .skipped
        }

        // The screen keeps its loaded plan across a leave-and-return, so it
        // can be stale by the time this runs, e.g. an automatic push already
        // wrote a newer local battery in the meantime.
        if let serverUpdatedAt = op.serverUpdatedAt,
           let localMTime = saveStore.batteryModifiedAt(romId: op.romId), localMTime >= serverUpdatedAt {
            return .skipped
        }

        do {
            let data = try await downloadSaveUseCase.execute(id: saveId, deviceId: deviceId, sessionId: nil)
            try saveStore.writeBattery(romId: op.romId, data: data)
            // Preserve the server's timestamp, matching the automatic path, so
            // a later compare is not skewed by clock drift after the write.
            if let serverUpdatedAt = op.serverUpdatedAt {
                try? saveStore.setBatteryModifiedAt(romId: op.romId, date: serverUpdatedAt)
            }
        } catch {
            return .failed("ROM \(op.romId): battery download failed (\(error.localizedDescription))")
        }

        await confirmDownload(saveId: saveId, deviceId: deviceId)
        return .downloaded
    }

    /// Tells the server this device now has the save's content. Best-effort:
    /// a failed confirmation only means the next negotiate may plan this same
    /// download again, never that the just-written local save is undone.
    private func confirmDownload(saveId: Int, deviceId: String) async {
        do {
            _ = try await confirmSaveDownloadUseCase.execute(id: saveId, deviceId: deviceId)
        } catch {
            logger.warning("Download confirmation failed (save \(saveId)): \(error.localizedDescription)")
        }
    }

    // MARK: - Save states (this device)

    /// Negotiate's id namespace mixes saves and states, so states are synced
    /// on their own, through the same `StateSyncCoordinator` the automatic
    /// pre-launch pull uses.
    private func runStatesSync(romId: Int) async -> [StepOutcome] {
        await stateSyncCoordinator.syncStates(romId: romId, mode: .bidirectional).map(mapSlotOutcome)
    }

    private func mapSlotOutcome(_ outcome: StateSyncCoordinator.SlotOutcome) -> StepOutcome {
        switch outcome {
        case .uploaded: return .uploaded
        case .downloaded: return .downloaded
        case .skipped, .recordedBaseline: return .skipped
        case .failed(let message): return .failed(message)
        }
    }

    // MARK: - External emulator apps (upload only)

    /// Uploads a matched external save only when it is newer than what the
    /// server already has for that ROM. Nothing is ever written back into the
    /// app's folder; reading only happens inside the folder's security scope.
    ///
    /// These files were never part of the negotiated plan, so unlike the
    /// battery uploads above this never sends a `sessionId`.
    private func runExternalUploads(
        scans: [ExternalEmulatorID: ExternalSaveScan],
        deviceId: String
    ) async -> [ExternalEmulatorID: [StepOutcome]] {
        var outcomes: [ExternalEmulatorID: [StepOutcome]] = [:]
        // Several matched files (even across different external apps) can
        // point at the same ROM; fetch that ROM's server saves once per run
        // instead of once per file.
        var serverSavesByRomId: [Int: [SaveSchema]] = [:]
        for (emulator, scan) in scans {
            guard !scan.matched.isEmpty, let grant = externalSaveFolderStore.grantedFolder(for: emulator) else { continue }
            // An entry even when nothing had to be uploaded, so the overview
            // can tell "everything already up there" apart from an app this
            // run never looked at.
            var appOutcomes: [StepOutcome] = []
            for file in scan.matched {
                let existing: [SaveSchema]
                if let cached = serverSavesByRomId[file.romId] {
                    existing = cached
                } else {
                    existing = (try? await listServerSavesUseCase.execute(romId: file.romId)) ?? []
                    serverSavesByRomId[file.romId] = existing
                }
                if let outcome = await runExternalUpload(file: file, emulator: emulator, grant: grant, existing: existing, deviceId: deviceId) {
                    appOutcomes.append(outcome)
                }
            }
            outcomes[emulator] = appOutcomes
        }
        return outcomes
    }

    private func runExternalUpload(
        file: ExternalSaveFile,
        emulator: ExternalEmulatorID,
        grant: ExternalSaveFolderGrant,
        existing: [SaveSchema],
        deviceId: String
    ) async -> StepOutcome? {
        // States and this ROM's own slot are not carried by an external app's
        // file listing, so the only freshness signal available here is a
        // straight timestamp compare against whatever the server already has.
        if let newestOnServer = existing.map(\.updatedAt).max(), file.modifiedAt <= newestOnServer {
            return nil
        }

        let data: Data
        do {
            data = try grant.withAccess { _ in try Data(contentsOf: file.url) }
        } catch {
            return .failed("\(emulator.emulator.displayName): could not read \(file.fileName) "
                + "(\(error.localizedDescription))")
        }

        do {
            _ = try await uploadSaveUseCase.execute(
                romId: file.romId,
                emulator: emulator.rawValue,
                slot: SaveSlot.battery,
                deviceId: deviceId,
                sessionId: nil,
                autocleanup: true,
                // Only reached when this file is newer than every row the
                // server holds for the ROM (see the check above), so the same
                // reasoning as the battery upload applies.
                overwrite: true,
                fileName: file.fileName,
                fileData: data,
                screenshotData: nil
            )
        } catch APIClientError.conflict {
            return .conflict
        } catch {
            return .failed("\(emulator.emulator.displayName): upload of \(file.fileName) failed "
                + "(\(error.localizedDescription))")
        }
        return .uploaded
    }

    // MARK: - Report bookkeeping

    private enum StepOutcome {
        case uploaded
        case downloaded
        case skipped
        /// The server rejected an upload with HTTP 409 (slot moved since this
        /// device's last sync). Counted alongside the conflicts negotiate
        /// already flagged up front, not as a failure.
        case conflict
        case failed(String)
    }

    /// Separate from `apply`: this only feeds the session-completion call,
    /// which must reflect the negotiated plan alone, not the report's full
    /// totals (see the `run` doc comment above).
    private func tally(_ outcome: StepOutcome, completed: inout Int, failed: inout Int) {
        switch outcome {
        case .uploaded, .downloaded:
            completed += 1
        case .failed:
            failed += 1
        case .skipped, .conflict:
            break
        }
    }

    /// The same outcome again, for the one app it belongs to. Its row says
    /// what happened to that app's saves, which the run totals cannot.
    private func apply(_ outcome: StepOutcome, to app: inout SaveSyncReport.ExternalAppOutcome) {
        switch outcome {
        case .uploaded: app.uploaded += 1
        case .failed: app.failed += 1
        case .conflict: app.conflicts += 1
        case .downloaded, .skipped: break
        }
    }

    private func apply(_ outcome: StepOutcome, to report: inout SaveSyncReport) {
        switch outcome {
        case .uploaded:
            report.uploaded += 1
        case .downloaded:
            report.downloaded += 1
        case .skipped:
            report.skipped += 1
        case .conflict:
            report.skippedConflicts += 1
        case .failed(let message):
            report.failed += 1
            report.errors.append(message)
            logger.error("\(message)")
        }
    }
}
