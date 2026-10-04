import Foundation

/// Orchestrates cloud sync of battery/state files against the RomM server for
/// a single emulator session. Lives at the Session layer (not as a UseCase) so
/// it can compose the individual sync UseCases without violating the
/// "no UseCase-inside-UseCase" rule.
@MainActor
final class CloudSaveSyncService {

    private let logger = Logger.sync

    struct Config {
        let romId: Int
        /// Server-side `emulator` tag used to group saves/states. Examples:
        /// "delta-ios" for DeltaCore, "libretro-pcsx-rearmed" for Libretro PSX.
        let emulator: String
        /// File-stem used for battery uploads. Web frontend identifies battery
        /// saves by filename; keep this stable across uploads for the same ROM.
        let batteryFileName: String
    }

    private let config: Config
    private let saveStore: PSaveStore
    private let listSavesUseCase: PListServerSavesUseCase
    private let uploadSaveUseCase: PUploadSaveUseCase
    private let updateSaveUseCase: PUpdateSaveUseCase
    private let downloadSaveUseCase: PDownloadSaveUseCase
    private let confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase
    private let settings: PCloudSaveSyncSettings
    private let recordSyncUseCase: PRecordSyncUseCase
    private let apiClient: PRommAPIClient
    private let syncDevice: PSyncDeviceRepository

    private var serverBatteryId: Int?
    /// When that row was last written, as far as this session knows. Updating
    /// it in place is only safe while the server still agrees (see
    /// `batteryTarget`).
    private var serverBatteryUpdatedAt: Date?
    /// Routes every state slot through the same decision logic `SaveSyncRunner`
    /// uses, so the two never grow different ideas of "changed".
    private let stateSyncCoordinator: StateSyncCoordinator

    init(
        config: Config,
        saveStore: PSaveStore,
        listSavesUseCase: PListServerSavesUseCase,
        uploadSaveUseCase: PUploadSaveUseCase,
        updateSaveUseCase: PUpdateSaveUseCase,
        downloadSaveUseCase: PDownloadSaveUseCase,
        confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase,
        listStatesUseCase: PListServerStatesUseCase,
        uploadStateUseCase: PUploadStateUseCase,
        updateStateUseCase: PUpdateStateUseCase,
        downloadStateUseCase: PDownloadStateUseCase,
        settings: PCloudSaveSyncSettings = CloudSaveSyncSettings.shared,
        recordSyncUseCase: PRecordSyncUseCase? = nil,
        apiClient: PRommAPIClient,
        syncDevice: PSyncDeviceRepository
    ) {
        self.config = config
        self.saveStore = saveStore
        self.listSavesUseCase = listSavesUseCase
        self.uploadSaveUseCase = uploadSaveUseCase
        self.updateSaveUseCase = updateSaveUseCase
        self.downloadSaveUseCase = downloadSaveUseCase
        self.confirmSaveDownloadUseCase = confirmSaveDownloadUseCase
        self.settings = settings
        self.recordSyncUseCase = recordSyncUseCase ?? RecordSyncUseCase(store: CloudSaveSyncSettings.shared)
        self.apiClient = apiClient
        self.syncDevice = syncDevice
        self.stateSyncCoordinator = StateSyncCoordinator(
            saveStore: saveStore,
            listStatesUseCase: listStatesUseCase,
            uploadStateUseCase: uploadStateUseCase,
            updateStateUseCase: updateStateUseCase,
            downloadStateUseCase: downloadStateUseCase
        )
    }

    var isEnabled: Bool { settings.isEnabled }

    // MARK: - Pull (download newer-than-local before emulator starts)

    /// Pulls saves/states newer than the local copy before the emulator starts.
    ///
    /// On RomM 5.0+ (issue #48) this first registers a device and runs a
    /// `negotiate` round: the server returns an explicit plan so we only touch
    /// what actually changed instead of blind-listing everything. States stay
    /// on the proven list-based pull as the authority; a successful negotiate
    /// owns the battery decision, otherwise we fall back to the legacy pull.
    /// Errors are swallowed and logged so a failed pull never blocks launch.
    /// An unreachable server is skipped up front, since each of the calls
    /// below would otherwise hold the launch until it times out.
    func pullBeforeLaunch() async {
        guard isEnabled else { return }
        guard await apiClient.isServerReachable() else {
            logger.info("Server not reachable, starting without a pull")
            return
        }
        let negotiated = await tryNegotiatedPull()
        if !negotiated {
            await pullBattery()
        }
        await pullStates()
        await learnBatteryUpdatedAt()
        recordSyncUseCase.execute(romId: config.romId, trigger: .automatic)
    }

    // MARK: - Negotiated pull (RomM 5.0+)

    /// Registers a device and negotiates a sync plan for this ROM. Returns
    /// `true` when negotiate succeeded (so the caller skips the legacy battery
    /// pull), `false` on an old server or any error (caller falls back).
    private func tryNegotiatedPull() async -> Bool {
        guard let deviceId = await syncDevice.deviceId() else { return false }
        let localStates = buildClientStates()
        let localHashByFile = Dictionary(localStates.map { ($0.fileName, $0.contentHash) },
                                         uniquingKeysWith: { a, _ in a })
        do {
            let response = try await apiClient.negotiateSync(
                SyncNegotiateRequest(deviceId: deviceId, saves: localStates, romIds: [config.romId])
            )
            logger.info("Negotiate ok: \(response.operations.count) ops "
                + "(down=\(response.totalDownload ?? 0) up=\(response.totalUpload ?? 0) "
                + "conflict=\(response.totalConflict ?? 0) noop=\(response.totalNoOp ?? 0))")
            // negotiate is global (ops span every ROM); only log/act on ours.
            for op in response.operations where op.romId == config.romId {
                let hashNote: String
                if let file = op.fileName, let mine = localHashByFile[file], let theirs = op.serverContentHash {
                    hashNote = (mine == theirs) ? " hash=match" : " hash=differ"
                } else {
                    hashNote = ""
                }
                logger.debug("  op \(op.action.rawValue) file=\(op.fileName ?? "?") slot=\(op.slot ?? "-") reason=\(op.reason ?? "-")\(hashNote)")
            }
            // `saveId` is filled on every action, not just `download` (a
            // `noOp` or `upload` verdict still names the row the server
            // already holds), so learn it here regardless of action.
            // Otherwise the next pushBattery() has no id to update and POSTs
            // a brand-new row instead of PUTting in place. State ops share
            // the same response and are excluded by their `.state` filename.
            //
            // There is no unique constraint on (rom_id, slot) server-side, so
            // more than one candidate row can come back for this ROM. Picking
            // deterministically (exact filename match, else the first
            // candidate) mirrors pullBattery()'s own tie-break below, instead
            // of letting whichever operation happens to sort last in the
            // response silently win and get overwritten by the next push.
            if let match = pickBatteryOperation(in: response.operations, requireSaveId: true) {
                serverBatteryId = match.saveId
                serverBatteryUpdatedAt = match.serverUpdatedAt
            }
            for op in response.operations where op.action == .download && op.romId == config.romId {
                await applyDownload(op)
            }
            return true
        } catch {
            logger.warning("Negotiate failed, using full sync: \(error.localizedDescription)")
            return false
        }
    }

    /// Snapshot of everything we hold locally for this ROM, with a content hash
    /// so the server can tell what actually changed.
    private func buildClientStates() -> [ClientSaveState] {
        var result: [ClientSaveState] = []

        if let battery = try? saveStore.readBattery(romId: config.romId), !battery.isEmpty {
            result.append(batteryClientState(data: battery))
        }

        let entries = (try? saveStore.listStates(romId: config.romId)) ?? []
        for entry in entries {
            guard let data = try? saveStore.readState(romId: config.romId, slot: entry.slot),
                  !data.isEmpty else { continue }
            result.append(ClientSaveState(
                romId: config.romId,
                fileName: StateSlots.fileName(slot: entry.slot),
                slot: String(entry.slot),
                emulator: config.emulator,
                contentHash: SaveContentHash.of(data),
                updatedAt: entry.modifiedAt,
                fileSizeBytes: data.count
            ))
        }
        return result
    }

    /// A negotiate operation is a battery operation when its file is not a
    /// `.state` and its slot is either unset (pre-slot server rows) or the
    /// battery slot itself. Shared by the `serverBatteryId` pick above and by
    /// `applyDownload` below so the two can never drift apart: a mismatch
    /// there would let a foreign-slot download get written into, and later
    /// pushed over, this device's own battery file.
    private func isBatteryOperation(_ op: SyncOperationSchema) -> Bool {
        guard let fileName = op.fileName else { return false }
        return !fileName.hasSuffix(".state") && (op.slot == nil || op.slot == SaveSlot.battery)
    }

    /// Picks the one battery operation for this ROM out of a negotiate
    /// response. There is no unique constraint on (rom_id, slot) server-side,
    /// so more than one candidate can come back; the exact filename match
    /// wins, else the first candidate, so the pick stays deterministic
    /// instead of depending on response order. `requireSaveId` is set by the
    /// pre-launch pull, which only cares about operations that name a row it
    /// can later update in place; the push path also needs the upload-without
    /// a row case, so it leaves this off.
    private func pickBatteryOperation(in operations: [SyncOperationSchema], requireSaveId: Bool = false) -> SyncOperationSchema? {
        let candidates = operations.filter { op in
            op.romId == config.romId && isBatteryOperation(op) && (!requireSaveId || op.saveId != nil)
        }
        return candidates.first(where: { $0.fileName == config.batteryFileName }) ?? candidates.first
    }

    /// Negotiate payload entry for the battery file. Shared by the pre-launch
    /// snapshot and the end-of-session push, which hands in the bytes it just
    /// flushed to disk instead of re-reading them.
    private func batteryClientState(data: Data) -> ClientSaveState {
        ClientSaveState(
            romId: config.romId,
            fileName: config.batteryFileName,
            slot: SaveSlot.battery,
            emulator: config.emulator,
            contentHash: SaveContentHash.of(data),
            updatedAt: saveStore.batteryModifiedAt(romId: config.romId) ?? Date(timeIntervalSince1970: 0),
            fileSizeBytes: data.count
        )
    }

    /// Applies a single `download` operation. States are intentionally left to
    /// `pullStates()` (its slot mapping is proven and the save/state id
    /// namespaces are ambiguous over negotiate), so only battery/save downloads
    /// are handled here.
    private func applyDownload(_ op: SyncOperationSchema) async {
        guard let saveId = op.saveId, isBatteryOperation(op) else { return }
        // Null-slot battery saves are never paired server-side (per the sync
        // API), so a `download` can point at the server's own battery. Only
        // overwrite a local battery when the server copy is provably newer,
        // mirroring pullBattery() — otherwise we'd clobber newer local progress.
        if let localMTime = saveStore.batteryModifiedAt(romId: config.romId) {
            guard let serverDate = op.serverUpdatedAt, serverDate > localMTime else { return }
        }
        do {
            let deviceId = await syncDevice.deviceId()
            let data = try await downloadSaveUseCase.execute(id: saveId, deviceId: deviceId, sessionId: nil)
            try saveStore.writeBattery(romId: config.romId, data: data)
            if let serverDate = op.serverUpdatedAt {
                try? saveStore.setBatteryModifiedAt(romId: config.romId, date: serverDate)
            }
            serverBatteryId = saveId
            serverBatteryUpdatedAt = op.serverUpdatedAt
            logger.info("Negotiate down: battery (\(data.count) bytes)")
            await confirmDownload(saveId: saveId, deviceId: deviceId)
        } catch {
            logger.error("Negotiate battery download failed (id=\(saveId)): \(error.localizedDescription)")
        }
    }

    private func pullBattery() async {
        do {
            let saves = try await listSavesUseCase.execute(romId: config.romId)
            let match = saves.first { $0.fileName == config.batteryFileName } ?? saves.first
            guard let match else { return }
            serverBatteryId = match.id
            serverBatteryUpdatedAt = match.updatedAt

            let localMTime = saveStore.batteryModifiedAt(romId: config.romId)
            if let localMTime, localMTime >= match.updatedAt { return }

            let deviceId = await syncDevice.deviceId()
            let data = try await downloadSaveUseCase.execute(id: match.id, deviceId: deviceId, sessionId: nil)
            try saveStore.writeBattery(romId: config.romId, data: data)
            // Preserve server mtime so subsequent local-vs-server compares are
            // not skewed by device clock drift after the write-to-disk timestamp.
            try? saveStore.setBatteryModifiedAt(romId: config.romId, date: match.updatedAt)
            logger.info("Battery pulled (\(data.count) bytes)")
            await confirmDownload(saveId: match.id, deviceId: deviceId)
        } catch {
            logger.error("Battery pull failed: \(error.localizedDescription)")
        }
    }

    /// Tells the server this device now has the save's content, so the next
    /// `negotiate` stops replanning the same download. Best effort: a failure
    /// here only means the next sync re-downloads something we already have.
    private func confirmDownload(saveId: Int, deviceId: String?) async {
        guard let deviceId else { return }
        do {
            _ = try await confirmSaveDownloadUseCase.execute(id: saveId, deviceId: deviceId)
        } catch {
            logger.warning("Download confirmation failed (id=\(saveId)): \(error.localizedDescription)")
        }
    }

    private func pullStates() async {
        let outcomes = await stateSyncCoordinator.syncStates(romId: config.romId, mode: .pullOnly)
        for outcome in outcomes {
            switch outcome {
            case .downloaded:
                logger.info("State pulled")
            case .failed(let message):
                logger.error(message)
            case .uploaded, .skipped, .recordedBaseline:
                break
            }
        }
    }

    // MARK: - Push (fire-and-forget after local write)

    func pushBattery(data: Data) {
        guard isEnabled else { return }
        Task { await self.pushBatteryAsync(data: data) }
    }

    /// Does the actual battery upload/update `pushBattery` fires and forgets.
    /// Split out, and awaitable, so it can be driven directly (e.g. by tests)
    /// instead of only observed indirectly through its side effects.
    ///
    /// Lets the server's `negotiate` verdict decide what to do with the just
    /// flushed bytes, the same way the pre-launch pull does, instead of the
    /// client comparing timestamps itself. Falls back to the legacy
    /// `batteryTarget()` path when there is no device id or negotiate itself
    /// fails (old server, offline), so those servers keep working unchanged.
    func pushBatteryAsync(data: Data) async {
        guard let deviceId = await syncDevice.deviceId() else {
            await pushBatteryViaLegacyTarget(data: data)
            return
        }
        let response: SyncNegotiateResponse
        do {
            response = try await apiClient.negotiateSync(SyncNegotiateRequest(
                deviceId: deviceId,
                saves: [batteryClientState(data: data)],
                romIds: [config.romId]
            ))
        } catch {
            logger.warning("Negotiate failed at push, falling back: \(error.localizedDescription)")
            await pushBatteryViaLegacyTarget(data: data)
            return
        }
        guard let operation = pickBatteryOperation(in: response.operations) else {
            logger.info("Battery push: negotiate named no verdict for this ROM")
            return
        }
        await applyBatteryPush(operation, data: data, deviceId: deviceId)
    }

    /// Acts on the negotiate verdict for the battery file.
    private func applyBatteryPush(_ operation: SyncOperationSchema, data: Data, deviceId: String) async {
        switch operation.action {
        case .noOp:
            logger.info("Battery unchanged, push skipped")
        case .upload:
            await uploadBattery(data: data, deviceId: deviceId, serverId: operation.saveId)
        case .conflict:
            // A user-facing force option is a later step; for now the row is
            // left alone rather than risking an overwrite of someone else's save.
            logger.warning("Battery push skipped: negotiate reported a conflict (\(operation.reason ?? "-"))")
        case .download:
            // The server holds a newer save; the next launch's pull picks it up.
            logger.info("Battery push skipped: server save is newer, next launch pulls it")
        case .unknown:
            logger.warning("Battery push skipped: unrecognized negotiate action")
        }
    }

    /// `serverId` set means there is an existing server row to update in
    /// place; nil means upload a fresh one. Shared by the negotiated push and
    /// its legacy fallback, which only differ in how they arrive at `serverId`.
    private func uploadBattery(data: Data, deviceId: String?, serverId: Int?) async {
        let cfg = config
        do {
            let result: SaveSchema
            if let serverId {
                result = try await updateSaveUseCase.execute(
                    id: serverId,
                    emulator: cfg.emulator,
                    deviceId: deviceId,
                    fileName: cfg.batteryFileName,
                    fileData: data,
                    screenshotData: nil
                )
            } else {
                result = try await uploadSaveUseCase.execute(
                    romId: cfg.romId,
                    emulator: cfg.emulator,
                    slot: SaveSlot.battery,
                    deviceId: deviceId,
                    sessionId: nil,
                    autocleanup: true,
                    // No `overwrite`: nothing here established that this device
                    // wins, so the server's guard is the only thing stopping a
                    // blind clobber of a row another device just wrote.
                    overwrite: nil,
                    fileName: cfg.batteryFileName,
                    fileData: data,
                    screenshotData: nil
                )
            }
            recordBattery(result)
            recordAutoSync()
            logger.info("Battery pushed id=\(result.id)")
        } catch APIClientError.conflict {
            // The slot moved since our last sync. Nothing to recover here,
            // the next negotiate/pull will pick up the current state.
            logger.warning("Battery push skipped: slot moved on the server (conflict)")
        } catch {
            logger.error("Battery push failed: \(error.localizedDescription)")
        }
    }

    /// Pre-negotiate push path: client-side timestamp comparison against the
    /// server row this session last read or wrote. Kept for servers negotiate
    /// is unavailable on (no device id registered, or the call itself failed).
    private func pushBatteryViaLegacyTarget(data: Data) async {
        switch await batteryTarget() {
        case .leaveAlone(let reason):
            logger.warning("Battery push skipped: \(reason)")
        case .update(let serverId):
            let deviceId = await syncDevice.deviceId()
            await uploadBattery(data: data, deviceId: deviceId, serverId: serverId)
        case .create:
            let deviceId = await syncDevice.deviceId()
            await uploadBattery(data: data, deviceId: deviceId, serverId: nil)
        }
    }

    /// The state (and thumbnail, if captured) is already written to disk by
    /// the caller before this is invoked, so this only has to trigger a sync
    /// for the slot; the coordinator re-reads it from disk itself.
    func pushState(slot: Int) {
        guard isEnabled else { return }
        Task { await self.pushStateAsync(slot: slot) }
    }

    /// Does the actual state sync `pushState` fires and forgets. Split out,
    /// and awaitable, so it can be driven directly (e.g. by tests) instead of
    /// only observed indirectly through its side effects.
    func pushStateAsync(slot: Int) async {
        let outcome = await stateSyncCoordinator.syncSlot(romId: config.romId, slot: slot, emulator: config.emulator)
        switch outcome {
        case .uploaded, .downloaded:
            recordAutoSync()
            logger.info("State slot \(slot) synced")
        case .failed(let message):
            logger.error(message)
        case .skipped, .recordedBaseline:
            break
        }
    }

    /// What a push may do with the row this session has been writing to.
    private enum BatteryTarget {
        /// No row known yet. The upload carries this device's id, so the
        /// server's own conflict guard decides.
        case create
        /// Still the row this session last read or wrote, safe to replace.
        case update(id: Int)
        /// It moved, or could not be checked. `PUT` has no conflict guard of
        /// its own, so this is the only thing between a push from a long
        /// session and a save another device wrote in the meantime.
        case leaveAlone(reason: String)
    }

    /// This narrows the window in which another device can write the row down
    /// to the gap between this check and the request that follows it, rather
    /// than closing it: `PUT` has no guard of its own to fall back on.
    private func batteryTarget() async -> BatteryTarget {
        guard let serverId = serverBatteryId else { return .create }

        let saves: [SaveSchema]
        do {
            saves = try await listSavesUseCase.execute(romId: config.romId)
        } catch {
            return .leaveAlone(reason: "could not check the server row (\(error.localizedDescription))")
        }
        guard let current = saves.first(where: { $0.id == serverId }) else {
            // Deleted, or pruned by autocleanup. A fresh upload is guarded.
            return .create
        }
        // No baseline, so there is nothing this could be compared against.
        // Writing anyway, because a session that never learned a timestamp
        // still has to get its save up (`learnBatteryUpdatedAt` keeps this
        // rare).
        guard let knownUpdatedAt = serverBatteryUpdatedAt else { return .update(id: serverId) }
        guard current.updatedAt <= knownUpdatedAt else {
            return .leaveAlone(reason: "another device wrote save \(serverId) in the meantime")
        }
        return .update(id: serverId)
    }

    /// A negotiate response may name the row without saying when it was last
    /// written, and a `noOp` verdict usually does. Without that timestamp the
    /// push at the end of the session has no baseline, so it is fetched here,
    /// while the row is still the one this device just read.
    private func learnBatteryUpdatedAt() async {
        guard let serverId = serverBatteryId, serverBatteryUpdatedAt == nil else { return }
        guard let saves = try? await listSavesUseCase.execute(romId: config.romId) else { return }
        serverBatteryUpdatedAt = saves.first(where: { $0.id == serverId })?.updatedAt
    }

    private func recordBattery(_ save: SaveSchema) {
        serverBatteryId = save.id
        serverBatteryUpdatedAt = save.updatedAt
    }
    private func recordAutoSync() { recordSyncUseCase.execute(romId: config.romId, trigger: .automatic) }
}
