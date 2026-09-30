import Foundation

protocol PApplySyncUseCase {
    /// Carries out a plan the server worked out, and closes its session.
    ///
    /// - Parameters:
    ///   - preview: The plan, exactly as it was shown. Not re-negotiated, so
    ///     the user applies what they read rather than something newer.
    ///   - resolutions: Which side wins, per conflicting operation. An entry
    ///     missing means undecided, and nothing is written for it.
    ///   - progress: Operations finished and operations planned, after each one.
    /// - Returns: What happened to every operation. Does not throw: a single
    ///   save that would not sync is reported, not a reason to abandon the rest.
    func execute(
        preview: SyncPreview,
        resolutions: [UUID: SyncConflictResolution],
        progress: @escaping @Sendable @MainActor (Int, Int) -> Void
    ) async -> SyncApplyReport
}

/// Applies a sync plan: uploads what only this device has, downloads what only
/// the server has, and for a conflict writes whichever side the user picked.
///
/// The one place in the app that overwrites a save the user did not ask to
/// overwrite, so it works out where a save goes before fetching it, refuses to
/// replace a file written since the plan was made, and keeps a copy of anything
/// it replaces in another app's folder.
///
/// Battery only, matching what negotiation reports.
final class ApplySyncUseCase: PApplySyncUseCase {

    /// What the plan says to do with one operation, after the user's choice for
    /// a conflict has been folded in.
    private enum Action {
        /// Push this device's save. `overwrite` replaces the server's copy,
        /// which only a conflict the local side won asks for.
        case upload(overwrite: Bool)
        case download
        case skip(SyncSkipReason)
    }

    /// Where a download is going, worked out before the bytes are fetched.
    private enum DownloadTarget {
        case internalStore
        case external(ExternalSaveDestination)
    }

    private enum DestinationLookup {
        case found(ExternalSaveDestination)
        case unavailable(SyncSkipReason)
    }

    private struct LocalSave {
        let data: Data
        /// The name the save carries here, which is not the server's: the
        /// server tags a slotted save with the time it took it.
        let fileName: String
    }

    private let logger = Logger.sync
    private let apiClient: PRommAPIClient
    private let saveStore: PSaveStore
    private let saveFiles: PExternalSaveFileRepository
    private let localROMs: PLocalROMRepository
    private let naming: ExternalSaveNaming

    init(
        apiClient: PRommAPIClient,
        saveStore: PSaveStore,
        saveFiles: PExternalSaveFileRepository,
        localROMs: PLocalROMRepository,
        handoffStore: PExternalEmulatorHandoffStore
    ) {
        self.apiClient = apiClient
        self.saveStore = saveStore
        self.saveFiles = saveFiles
        self.localROMs = localROMs
        self.naming = ExternalSaveNaming(handoffStore: handoffStore)
    }

    func execute(
        preview: SyncPreview,
        resolutions: [UUID: SyncConflictResolution],
        progress: @escaping @Sendable @MainActor (Int, Int) -> Void
    ) async -> SyncApplyReport {
        // Operations already in agreement drop out here, so they are neither
        // counted towards progress nor listed in the report.
        let planned = preview.operations.compactMap { op -> (SyncPreviewOperation, Action)? in
            Self.action(for: op, resolutions: resolutions).map { (op, $0) }
        }
        logger.info("Sync apply: \(planned.count) of \(preview.operations.count) operations to carry out")

        var outcomes: [SyncApplyOutcome] = []
        for (index, entry) in planned.enumerated() {
            let status = await apply(entry.0, action: entry.1, preview: preview)
            outcomes.append(SyncApplyOutcome(operation: entry.0, status: status))
            progress(index + 1, planned.count)
        }

        let applied = outcomes.filter { $0.status == .applied }.count
        let failed = outcomes.filter { $0.status.isFailure }.count
        logger.info("Sync apply: \(applied) applied, \(failed) failed, "
            + "\(outcomes.count - applied - failed) skipped")

        return SyncApplyReport(
            outcomes: outcomes,
            sessionClosed: await closeSession(preview.sessionId, completed: applied, failed: failed)
        )
    }

    // MARK: - Planning

    /// Nil for an operation that needs nothing done, so it never reaches the
    /// report. Every other direction resolves to something, including a
    /// conflict, whose answer comes from the user rather than from the plan.
    private static func action(
        for op: SyncPreviewOperation,
        resolutions: [UUID: SyncConflictResolution]
    ) -> Action? {
        switch op.direction {
        case .noOp:
            return nil
        case .upload:
            return .upload(overwrite: false)
        case .download:
            return .download
        case .conflict:
            switch resolutions[op.id] {
            case .keepLocal: return .upload(overwrite: true)
            case .takeServer: return .download
            case .skip: return .skip(.conflictSkipped)
            case nil: return .skip(.conflictNotResolved)
            }
        }
    }

    // MARK: - Applying

    private func apply(
        _ op: SyncPreviewOperation,
        action: Action,
        preview: SyncPreview
    ) async -> SyncApplyOutcome.Status {
        do {
            switch action {
            case .skip(let reason):
                return .skipped(reason)
            case .upload(let overwrite):
                // A slot this build does not own has no local save behind it
                // and nowhere to put a downloaded one.
                guard let source = op.source else { return .skipped(.unknownSource) }
                return try await upload(op, source: source, preview: preview, overwrite: overwrite)
            case .download:
                guard let source = op.source else { return .skipped(.unknownSource) }
                return try await download(op, source: source, preview: preview)
            }
        } catch {
            logger.warning("Sync apply failed for rom \(op.romId): \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private func upload(
        _ op: SyncPreviewOperation,
        source: SyncSaveSource,
        preview: SyncPreview,
        overwrite: Bool
    ) async throws -> SyncApplyOutcome.Status {
        guard let local = readLocalSave(op, source: source) else {
            return .skipped(.localSaveUnavailable)
        }

        // Replacing a save the server already has is its own endpoint. Which
        // one applies follows from the plan naming a server save, not from the
        // direction: whenever the slot is already filled there, filling it a
        // second time would leave the pair duplicated.
        if let saveId = op.saveId {
            _ = try await apiClient.updateSave(
                id: saveId,
                emulator: Self.attribution(for: source),
                deviceId: preview.deviceId,
                fileName: local.fileName,
                fileData: local.data,
                screenshotData: nil
            )
        } else {
            _ = try await apiClient.uploadSave(
                romId: op.romId,
                emulator: Self.attribution(for: source),
                slot: source.slot,
                deviceId: preview.deviceId,
                sessionId: preview.sessionId,
                overwrite: overwrite,
                fileName: local.fileName,
                fileData: local.data,
                screenshotData: nil
            )
        }
        return .applied
    }

    private func download(
        _ op: SyncPreviewOperation,
        source: SyncSaveSource,
        preview: SyncPreview
    ) async throws -> SyncApplyOutcome.Status {
        guard let saveId = op.saveId else { return .skipped(.noServerSave) }

        // Settled before the bytes are asked for: downloading a save there is
        // no home for would report it to the server as taken and leave the
        // device without it.
        let target: DownloadTarget
        switch source {
        case .internalStore:
            guard !Self.wasWrittenSince(
                op.localUpdatedAt,
                current: saveStore.batteryModifiedAt(romId: op.romId)
            ) else { return .skipped(.localSaveChanged) }
            target = .internalStore

        case .externalApp(let emulator):
            switch externalDestination(for: op, emulator: emulator) {
            case .unavailable(let reason):
                return .skipped(reason)
            case .found(let destination):
                guard !Self.wasWrittenSince(
                    op.localUpdatedAt,
                    current: destination.existingModifiedAt
                ) else { return .skipped(.localSaveChanged) }
                target = .external(destination)
            }
        }

        // Not optimistic: the server counts the save as taken only once this
        // device confirms it, so a write that fails does not read as a sync.
        let data = try await apiClient.downloadSave(
            id: saveId,
            deviceId: preview.deviceId,
            sessionId: preview.sessionId,
            optimistic: false
        )

        // Stamped with the server's time rather than now, or the next
        // negotiation reports the save just taken as the newer of the two and
        // plans to send it straight back.
        let modifiedAt = op.serverUpdatedAt ?? Date()
        switch target {
        case .internalStore:
            try saveStore.writeBattery(romId: op.romId, data: data)
            try saveStore.setBatteryModifiedAt(romId: op.romId, date: modifiedAt)
        case .external(let destination):
            try saveFiles.write(data, to: destination, modifiedAt: modifiedAt)
        }

        try await apiClient.confirmSaveDownloaded(id: saveId, deviceId: preview.deviceId)
        return .applied
    }

    // MARK: - Local files

    private func readLocalSave(
        _ op: SyncPreviewOperation,
        source: SyncSaveSource
    ) -> LocalSave? {
        switch source {
        case .internalStore:
            guard let data = try? saveStore.readBattery(romId: op.romId), !data.isEmpty else {
                return nil
            }
            return LocalSave(data: data, fileName: SaveSlot.batteryFileName)

        case .externalApp(let emulator):
            // Read through the repository rather than from the URL: the scan's
            // URLs only resolve inside the granted folder's security scope.
            guard let file = op.externalFile,
                  let data = saveFiles.readSaves(at: [file.url], for: emulator)[file.url],
                  !data.isEmpty else { return nil }
            return LocalSave(data: data, fileName: file.fileName)
        }
    }

    private func externalDestination(
        for op: SyncPreviewOperation,
        emulator: ExternalEmulatorID
    ) -> DestinationLookup {
        guard let layout = emulator.emulator.saveLayout else {
            return .unavailable(.unknownSource)
        }
        guard let rom = downloadedROM(id: op.romId) else {
            return .unavailable(.romNotAvailable)
        }
        guard let baseName = naming.writeBaseName(for: rom, emulator: emulator, layout: layout) else {
            return .unavailable(.saveNameUnknown)
        }
        guard let destination = saveFiles.destination(for: emulator, baseName: baseName) else {
            return .unavailable(.noWritableDestination)
        }
        return .found(destination)
    }

    private func downloadedROM(id: Int) -> DownloadedROM? {
        do {
            return try localROMs.getDownloadedROM(byId: id)
        } catch {
            logger.warning("Could not look up rom \(id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    /// True when the file on this device is newer than the one the plan was
    /// made against, which makes the plan's verdict about it out of date.
    ///
    /// A second of slack, because modification dates come back at whole-second
    /// resolution on some volumes and a file that never changed would otherwise
    /// read as rewritten. No date reported at all with a file now present means
    /// the save appeared after the preview, which counts as written.
    private static func wasWrittenSince(_ reported: Date?, current: Date?) -> Bool {
        guard let current else { return false }
        guard let reported else { return true }
        return current.timeIntervalSince(reported) > 1
    }

    /// The app the server credits a save to. Attribution only: pairing keys on
    /// the slot, so this names the writer without deciding anything.
    private static func attribution(for source: SyncSaveSource) -> String? {
        switch source {
        case .internalStore: return nil
        case .externalApp(let emulator): return emulator.rawValue
        }
    }

    /// Reports the outcome so the server closes the session negotiation opened.
    ///
    /// Failing here leaves the session open but the saves moved, so it is
    /// reported rather than thrown: retrying would apply the plan twice.
    private func closeSession(_ id: Int?, completed: Int, failed: Int) async -> Bool {
        guard let id else { return true }
        do {
            let session = try await apiClient.completeSyncSession(
                id: id,
                operationsCompleted: completed,
                operationsFailed: failed
            )
            logger.info("Sync session \(id) closed as \(session.status)")
            return true
        } catch {
            logger.warning("Sync session \(id) could not be closed: \(error.localizedDescription)")
            return false
        }
    }
}
