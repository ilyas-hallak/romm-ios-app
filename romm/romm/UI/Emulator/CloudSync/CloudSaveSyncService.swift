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
        settings: CloudSaveSyncSettings = .shared
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
            print("[CloudSync] battery pulled (\(data.count) bytes)")
        } catch {
            print("[CloudSync] battery pull failed: \(error.localizedDescription)")
        }
    }

    private func pullStates() async {
        do {
            let states = try await listStatesUseCase.execute(romId: config.romId)
            for s in states {
                guard let slot = Self.slotFromFileName(s.fileName) else { continue }
                serverStateIdBySlot[slot] = s.id

                let localMTime = saveStore.stateModifiedAt(romId: config.romId, slot: slot)
                if let localMTime, localMTime >= s.updatedAt { continue }

                let data = try await downloadStateUseCase.execute(id: s.id)
                try saveStore.writeState(romId: config.romId, slot: slot, data: data)
                try? saveStore.setStateModifiedAt(romId: config.romId, slot: slot, date: s.updatedAt)
                print("[CloudSync] state slot \(slot) pulled (\(data.count) bytes)")
            }
        } catch {
            print("[CloudSync] states pull failed: \(error.localizedDescription)")
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
                print("[CloudSync] battery pushed id=\(result.id)")
            } catch {
                print("[CloudSync] battery push failed: \(error.localizedDescription)")
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
                print("[CloudSync] state slot \(slot) pushed id=\(result.id)")
            } catch {
                print("[CloudSync] state slot \(slot) push failed: \(error.localizedDescription)")
            }
        }
    }

    private func recordBatteryId(_ id: Int) { serverBatteryId = id }
    private func recordStateId(slot: Int, id: Int) { serverStateIdBySlot[slot] = id }

    // MARK: - Filename helpers

    static func stateFileName(slot: Int) -> String { "slot\(slot).state" }

    /// Parses `slotN.state` (or `slotN.*`) back to slot index `N`.
    static func slotFromFileName(_ name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("slot") else { return nil }
        return Int(stem.dropFirst("slot".count))
    }
}
