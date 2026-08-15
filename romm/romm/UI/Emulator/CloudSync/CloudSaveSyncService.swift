import Foundation

/// Orchestrates cloud sync of battery/state files against the RomM server for
/// a single emulator session. Lives at the Session layer (not as a UseCase) so
/// it can compose the individual sync UseCases without violating the
/// "no UseCase-inside-UseCase" rule.
@MainActor
final class CloudSaveSyncService {

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
    private let recordSyncUseCase: PRecordSyncUseCase
    private let logger = Logger.sync

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
        recordSyncUseCase: PRecordSyncUseCase? = nil
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
        self.recordSyncUseCase = recordSyncUseCase ?? RecordSyncUseCase(store: settings)
    }

    var isEnabled: Bool { settings.isEnabled }

    // MARK: - Pull (download newer-than-local before emulator starts)

    /// Lists server saves/states for this ROM and pulls any that are newer
    /// than the corresponding local file. Errors are swallowed and logged so a
    /// failed pull never blocks emulator launch.
    func pullBeforeLaunch() async {
        guard isEnabled else { return }
        await pullBattery()
        await pullStates()
        recordSyncUseCase.execute(romId: config.romId, trigger: .automatic)
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
                await self.recordAutoSync()
                logger.info("Battery pushed id=\(result.id)")
            } catch {
                logger.error("Battery push failed: \(error.localizedDescription)")
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
                await self.recordAutoSync()
                logger.info("State slot \(slot) pushed id=\(result.id)")
            } catch {
                logger.error("State slot \(slot) push failed: \(error.localizedDescription)")
            }
        }
    }

    private func recordBatteryId(_ id: Int) { serverBatteryId = id }
    private func recordStateId(slot: Int, id: Int) { serverStateIdBySlot[slot] = id }
    private func recordAutoSync() { recordSyncUseCase.execute(romId: config.romId, trigger: .automatic) }

    // MARK: - Filename helpers

    static func stateFileName(slot: Int) -> String { "slot\(slot).state" }

    /// Parses `slotN.state` (or `slotN.*`) back to slot index `N`.
    static func slotFromFileName(_ name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("slot") else { return nil }
        return Int(stem.dropFirst("slot".count))
    }
}
