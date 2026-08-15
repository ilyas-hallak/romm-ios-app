import Foundation
import CryptoKit

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
    private let listStatesUseCase: PListServerStatesUseCase
    private let uploadStateUseCase: PUploadStateUseCase
    private let updateStateUseCase: PUpdateStateUseCase
    private let downloadStateUseCase: PDownloadStateUseCase
    private let settings: CloudSaveSyncSettings
    private let apiClient: PRommAPIClient
    private let syncDevice: PSyncDeviceRepository

    private var serverBatteryId: Int?
    private var serverStateIdBySlot: [Int: Int] = [:]

    init(
        config: Config,
        saveStore: PSaveStore,
        listSavesUseCase: PListServerSavesUseCase,
        uploadSaveUseCase: PUploadSaveUseCase,
        updateSaveUseCase: PUpdateSaveUseCase,
        downloadSaveUseCase: PDownloadSaveUseCase,
        listStatesUseCase: PListServerStatesUseCase,
        uploadStateUseCase: PUploadStateUseCase,
        updateStateUseCase: PUpdateStateUseCase,
        downloadStateUseCase: PDownloadStateUseCase,
        settings: CloudSaveSyncSettings = .shared,
        apiClient: PRommAPIClient = RommAPIClient.shared,
        syncDevice: PSyncDeviceRepository = SyncDeviceRepository.shared
    ) {
        self.config = config
        self.saveStore = saveStore
        self.listSavesUseCase = listSavesUseCase
        self.uploadSaveUseCase = uploadSaveUseCase
        self.updateSaveUseCase = updateSaveUseCase
        self.downloadSaveUseCase = downloadSaveUseCase
        self.listStatesUseCase = listStatesUseCase
        self.uploadStateUseCase = uploadStateUseCase
        self.updateStateUseCase = updateStateUseCase
        self.downloadStateUseCase = downloadStateUseCase
        self.settings = settings
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
                slot: nil,
                emulator: config.emulator,
                contentHash: Self.contentHash(battery),
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
                fileName: Self.stateFileName(slot: entry.slot),
                slot: String(entry.slot),
                emulator: config.emulator,
                contentHash: Self.contentHash(data),
                updatedAt: entry.modifiedAt,
                fileSizeBytes: data.count
            ))
        }
        return result
    }

    /// Applies a single `download` operation. States are intentionally left to
    /// `pullStates()` (its slot mapping is proven and the save/state id
    /// namespaces are ambiguous over negotiate), so only battery/save downloads
    /// are handled here.
    private func applyDownload(_ op: SyncOperationSchema) async {
        guard let saveId = op.saveId, let fileName = op.fileName else { return }
        guard !fileName.hasSuffix(".state") else { return }
        // Null-slot battery saves are never paired server-side (per the sync
        // API), so a `download` can point at the server's own battery. Only
        // overwrite a local battery when the server copy is provably newer,
        // mirroring pullBattery() — otherwise we'd clobber newer local progress.
        if let localMTime = saveStore.batteryModifiedAt(romId: config.romId) {
            guard let serverDate = op.serverUpdatedAt, serverDate > localMTime else { return }
        }
        do {
            let data = try await downloadSaveUseCase.execute(id: saveId)
            try saveStore.writeBattery(romId: config.romId, data: data)
            if let serverDate = op.serverUpdatedAt {
                try? saveStore.setBatteryModifiedAt(romId: config.romId, date: serverDate)
            }
            serverBatteryId = saveId
            logger.info("Negotiate down: battery (\(data.count) bytes)")
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

            let localMTime = saveStore.batteryModifiedAt(romId: config.romId)
            if let localMTime, localMTime >= match.updatedAt { return }

            let data = try await downloadSaveUseCase.execute(id: match.id)
            try saveStore.writeBattery(romId: config.romId, data: data)
            // Preserve server mtime so subsequent local-vs-server compares are
            // not skewed by device clock drift after the write-to-disk timestamp.
            try? saveStore.setBatteryModifiedAt(romId: config.romId, date: match.updatedAt)
            logger.info("Battery pulled (\(data.count) bytes)")
        } catch {
            logger.error("Battery pull failed: \(error.localizedDescription)")
        }
    }

    private func pullStates() async {
        do {
            let states = try await listStatesUseCase.execute(romId: config.romId)

            // First pass: map states with a recognizable `slotN.state` name to
            // their real slot. States with any other server-side name (e.g.
            // "Chrono Trigger (USA) [2026-05-06 ...].state") are collected so we
            // can assign them synthetic slots that never collide with real ones.
            var realSlots = Set<Int>()
            var unnamed: [StateSchema] = []
            for s in states {
                if let slot = Self.slotFromFileName(s.fileName) {
                    realSlots.insert(slot)
                } else {
                    unnamed.append(s)
                }
            }

            // Deterministically order the unnamed states (by updatedAt, then id)
            // so the same server state maps to the same synthetic slot across
            // launches, then hand each the next free slot index.
            let ordered = unnamed.sorted {
                $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt < $1.updatedAt
            }
            // Cap at the highest slot the UI can display (slots 0…20 = 21 total,
            // see EmulatorMenuSheet). Anything beyond that has no visible slot.
            let maxSlot = 20
            var syntheticSlotByStateId: [Int: Int] = [:]
            var nextSlot = 0
            var overflow = 0
            for s in ordered {
                while realSlots.contains(nextSlot) { nextSlot += 1 }
                guard nextSlot <= maxSlot else { overflow += 1; continue }
                syntheticSlotByStateId[s.id] = nextSlot
                realSlots.insert(nextSlot)
            }
            if overflow > 0 {
                logger.warning("\(overflow) server state(s) skipped: no free slot (max \(maxSlot + 1))")
            }

            for s in states {
                guard let slot = Self.slotFromFileName(s.fileName) ?? syntheticSlotByStateId[s.id] else { continue }
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
        let cfg = config
        let serverId = serverBatteryId
        Task { [uploadSaveUseCase, updateSaveUseCase] in
            do {
                let result: SaveSchema
                if let serverId {
                    result = try await updateSaveUseCase.execute(
                        id: serverId,
                        emulator: cfg.emulator,
                        fileName: cfg.batteryFileName,
                        fileData: data,
                        screenshotData: nil
                    )
                } else {
                    result = try await uploadSaveUseCase.execute(
                        romId: cfg.romId,
                        emulator: cfg.emulator,
                        slot: nil,
                        fileName: cfg.batteryFileName,
                        fileData: data,
                        screenshotData: nil
                    )
                }
                await self.recordBatteryId(result.id)
                self.logger.info("Battery pushed id=\(result.id)")
            } catch {
                self.logger.error("Battery push failed: \(error.localizedDescription)")
            }
        }
    }

    func pushState(slot: Int, data: Data, thumbnail: Data?) {
        guard isEnabled else { return }
        let cfg = config
        let fileName = Self.stateFileName(slot: slot)
        let serverId = serverStateIdBySlot[slot]
        Task { [uploadStateUseCase, updateStateUseCase] in
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
                await self.recordStateId(slot: slot, id: result.id)
                self.logger.info("State slot \(slot) pushed id=\(result.id)")
            } catch {
                self.logger.error("State slot \(slot) push failed: \(error.localizedDescription)")
            }
        }
    }

    private func recordBatteryId(_ id: Int) { serverBatteryId = id }
    private func recordStateId(slot: Int, id: Int) { serverStateIdBySlot[slot] = id }

    // MARK: - Filename helpers

    static func stateFileName(slot: Int) -> String { "slot\(slot).state" }

    /// MD5 hex of a save/state blob, sent to the server as `content_hash`.
    /// RomM hashes saves with MD5 server-side (verified against a live 5.1
    /// server), so we must match that to let it detect real content changes.
    static func contentHash(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Parses `slotN.state` (or `slotN.*`) back to slot index `N`.
    static func slotFromFileName(_ name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("slot") else { return nil }
        return Int(stem.dropFirst("slot".count))
    }
}
