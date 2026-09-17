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
    private let listStatesUseCase: PListServerStatesUseCase
    private let uploadStateUseCase: PUploadStateUseCase
    private let updateStateUseCase: PUpdateStateUseCase
    private let downloadStateUseCase: PDownloadStateUseCase
    private let settings: PCloudSaveSyncSettings
    private let recordSyncUseCase: PRecordSyncUseCase
    private let apiClient: PRommAPIClient
    private let syncDevice: PSyncDeviceRepository

    private var serverBatteryId: Int?
    /// When that row was last written, as far as this session knows. Updating
    /// it in place is only safe while the server still agrees (see
    /// `batteryTarget`).
    private var serverBatteryUpdatedAt: Date?
    private var serverStateIdBySlot: [Int: Int] = [:]

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
        self.listStatesUseCase = listStatesUseCase
        self.uploadStateUseCase = uploadStateUseCase
        self.updateStateUseCase = updateStateUseCase
        self.downloadStateUseCase = downloadStateUseCase
        self.settings = settings
        self.recordSyncUseCase = recordSyncUseCase ?? RecordSyncUseCase(store: CloudSaveSyncSettings.shared)
        self.apiClient = apiClient
        self.syncDevice = syncDevice
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
    func pullBeforeLaunch() async {
        guard isEnabled else { return }
        let negotiated = await tryNegotiatedPull()
        if !negotiated {
            await pullBattery()
        }
        await pullStates()
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
                SyncNegotiateRequest(deviceId: deviceId, saves: localStates)
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
            let batteryCandidates = response.operations.filter { op in
                op.romId == config.romId && op.saveId != nil && isBatteryOperation(op)
            }
            if let match = batteryCandidates.first(where: { $0.fileName == config.batteryFileName }) ?? batteryCandidates.first {
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
            result.append(ClientSaveState(
                romId: config.romId,
                fileName: config.batteryFileName,
                slot: SaveSlot.battery,
                emulator: config.emulator,
                contentHash: SaveContentHash.of(battery),
                updatedAt: saveStore.batteryModifiedAt(romId: config.romId) ?? Date(timeIntervalSince1970: 0),
                fileSizeBytes: battery.count
            ))
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
        do {
            let states = try await listStatesUseCase.execute(romId: config.romId)

            let (slotByStateId, overflow) = StateSlots.assign(states.map {
                StateSlots.Candidate(id: $0.id, fileName: $0.fileName, updatedAt: $0.updatedAt)
            })
            if overflow > 0 {
                logger.warning("\(overflow) server state(s) skipped: no free slot (max 21)")
            }

            for s in states {
                guard let slot = slotByStateId[s.id] else { continue }
                serverStateIdBySlot[slot] = s.id

                let localMTime = saveStore.stateModifiedAt(romId: config.romId, slot: slot)
                if let localMTime, localMTime >= s.updatedAt { continue }

                let data = try await downloadStateUseCase.execute(id: s.id)
                try saveStore.writeState(romId: config.romId, slot: slot, data: data)
                try? saveStore.setStateModifiedAt(romId: config.romId, slot: slot, date: s.updatedAt)
                logger.info("State slot \(slot) pulled (\(data.count) bytes)")
            }
        } catch {
            logger.error("States pull failed: \(error.localizedDescription)")
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
    func pushBatteryAsync(data: Data) async {
        let cfg = config
        do {
            let result: SaveSchema
            switch await batteryTarget() {
            case .leaveAlone(let reason):
                logger.warning("Battery push skipped: \(reason)")
                return
            case .update(let serverId):
                result = try await updateSaveUseCase.execute(
                    id: serverId,
                    emulator: cfg.emulator,
                    fileName: cfg.batteryFileName,
                    fileData: data,
                    screenshotData: nil
                )
            case .create:
                let deviceId = await syncDevice.deviceId()
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

    func pushState(slot: Int, data: Data, thumbnail: Data?) {
        guard isEnabled else { return }
        Task { await self.pushStateAsync(slot: slot, data: data, thumbnail: thumbnail) }
    }

    /// Does the actual state upload/update `pushState` fires and forgets.
    /// Split out, and awaitable, so it can be driven directly (e.g. by tests)
    /// instead of only observed indirectly through its side effects.
    func pushStateAsync(slot: Int, data: Data, thumbnail: Data?) async {
        let cfg = config
        let fileName = StateSlots.fileName(slot: slot)
        let serverId = serverStateIdBySlot[slot]
        do {
            let result: StateSchema
            if let serverId {
                result = try await updateStateUseCase.execute(
                    id: serverId,
                    emulator: cfg.emulator,
                    fileName: fileName,
                    fileData: data,
                    screenshotData: thumbnail
                )
            } else {
                result = try await uploadStateUseCase.execute(
                    romId: cfg.romId,
                    emulator: cfg.emulator,
                    fileName: fileName,
                    fileData: data,
                    screenshotData: thumbnail
                )
            }
            recordStateId(slot: slot, id: result.id)
            recordAutoSync()
            logger.info("State slot \(slot) pushed id=\(result.id)")
        } catch {
            logger.error("State slot \(slot) push failed: \(error.localizedDescription)")
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

    private func batteryTarget() async -> BatteryTarget {
        guard let serverId = serverBatteryId else { return .create }
        // Nothing to compare against, so leave the row as the only thing this
        // session knows and update it, as before.
        guard let knownUpdatedAt = serverBatteryUpdatedAt else { return .update(id: serverId) }

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
        guard current.updatedAt <= knownUpdatedAt else {
            return .leaveAlone(reason: "another device wrote save \(serverId) in the meantime")
        }
        return .update(id: serverId)
    }

    private func recordBattery(_ save: SaveSchema) {
        serverBatteryId = save.id
        serverBatteryUpdatedAt = save.updatedAt
    }
    private func recordStateId(slot: Int, id: Int) { serverStateIdBySlot[slot] = id }
    private func recordAutoSync() { recordSyncUseCase.execute(romId: config.romId, trigger: .automatic) }
}
