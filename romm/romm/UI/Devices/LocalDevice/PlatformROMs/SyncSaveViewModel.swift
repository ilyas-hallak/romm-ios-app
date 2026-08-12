import Foundation
import Observation

@Observable
@MainActor
final class SyncSaveViewModel {
    let rom: DownloadedROM

    var serverStates: [StateSchema] = []
    var serverSaves: [SaveSchema] = []
    var localStates: [SaveStateEntry] = []
    var hasLocalBattery = false
    var localBatteryDate: Date?
    var isLoadingServer = false
    var downloadingStateIds: Set<Int> = []
    var downloadingSaveIds: Set<Int> = []
    var uploadingStateSlots: Set<Int> = []
    var isUploadingBattery = false
    var errorMessage: String?
    var pendingUpload: PendingUpload?
    var lastSyncMeta: SyncMetadata?

    private let syncSettings = CloudSaveSyncSettings.shared

    private let listSavesUseCase: PListServerSavesUseCase
    private let listStatesUseCase: PListServerStatesUseCase
    private let downloadSaveUseCase: PDownloadSaveUseCase
    private let downloadStateUseCase: PDownloadStateUseCase
    private let uploadSaveUseCase: PUploadSaveUseCase
    private let updateSaveUseCase: PUpdateSaveUseCase
    private let uploadStateUseCase: PUploadStateUseCase
    private let updateStateUseCase: PUpdateStateUseCase
    private let saveStore: PSaveStore

    init(
        rom: DownloadedROM,
        listSavesUseCase: PListServerSavesUseCase,
        listStatesUseCase: PListServerStatesUseCase,
        downloadSaveUseCase: PDownloadSaveUseCase,
        downloadStateUseCase: PDownloadStateUseCase,
        uploadSaveUseCase: PUploadSaveUseCase,
        updateSaveUseCase: PUpdateSaveUseCase,
        uploadStateUseCase: PUploadStateUseCase,
        updateStateUseCase: PUpdateStateUseCase,
        saveStore: PSaveStore
    ) {
        self.rom = rom
        self.listSavesUseCase = listSavesUseCase
        self.listStatesUseCase = listStatesUseCase
        self.downloadSaveUseCase = downloadSaveUseCase
        self.downloadStateUseCase = downloadStateUseCase
        self.uploadSaveUseCase = uploadSaveUseCase
        self.updateSaveUseCase = updateSaveUseCase
        self.uploadStateUseCase = uploadStateUseCase
        self.updateStateUseCase = updateStateUseCase
        self.saveStore = saveStore
    }

    // MARK: - Load

    func loadAll() async {
        isLoadingServer = true
        do {
            async let statesTask = listStatesUseCase.execute(romId: rom.id)
            async let savesTask = listSavesUseCase.execute(romId: rom.id)
            let (states, saves) = try await (statesTask, savesTask)
            serverStates = states
            serverSaves = saves
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingServer = false
        localStates = (try? saveStore.listStates(romId: rom.id)) ?? []
        localBatteryDate = saveStore.batteryModifiedAt(romId: rom.id)
        hasLocalBattery = localBatteryDate != nil
        lastSyncMeta = syncSettings.lastSync(romId: rom.id)
    }

    private func recordManualSync() {
        syncSettings.recordSync(romId: rom.id, trigger: .manual)
        lastSyncMeta = syncSettings.lastSync(romId: rom.id)
    }

    // MARK: - Download

    func downloadServerState(_ state: StateSchema) {
        guard !downloadingStateIds.contains(state.id) else { return }
        if state.missingFromFs {
            errorMessage = "File missing on server — upload it again."
            return
        }
        downloadingStateIds.insert(state.id)
        Task {
            defer { downloadingStateIds.remove(state.id) }
            do {
                let data = try await downloadStateUseCase.execute(id: state.id)
                guard !data.isEmpty else { errorMessage = "Server returned empty file."; return }
                let slot = slotFromFileName(state.fileName) ?? 0
                try saveStore.writeState(romId: rom.id, slot: slot, data: data)
                localStates = (try? saveStore.listStates(romId: rom.id)) ?? []
                recordManualSync()
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    func downloadServerSave(_ save: SaveSchema) {
        guard !downloadingSaveIds.contains(save.id) else { return }
        if save.missingFromFs {
            errorMessage = "File missing on server — upload it again."
            return
        }
        downloadingSaveIds.insert(save.id)
        Task {
            defer { downloadingSaveIds.remove(save.id) }
            do {
                let data = try await downloadSaveUseCase.execute(id: save.id)
                guard !data.isEmpty else { errorMessage = "Server returned empty file."; return }
                try saveStore.writeBattery(romId: rom.id, data: data)
                hasLocalBattery = true
                recordManualSync()
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Upload

    func uploadLocalState(entry: SaveStateEntry) {
        let existingId = serverStates.first { slotFromFileName($0.fileName) == entry.slot }?.id
        let pending = PendingUpload.state(slot: entry.slot, existingId: existingId)
        existingId != nil ? (pendingUpload = pending) : executeUpload(pending, update: false)
    }

    func uploadLocalBattery() {
        let existingId = serverSaves.first?.id
        let pending = PendingUpload.battery(existingId: existingId)
        existingId != nil ? (pendingUpload = pending) : executeUpload(pending, update: false)
    }

    func confirmUpload(update: Bool) {
        guard let pending = pendingUpload else { return }
        pendingUpload = nil
        executeUpload(pending, update: update)
    }

    func cancelPendingUpload() { pendingUpload = nil }

    private func executeUpload(_ pending: PendingUpload, update: Bool) {
        switch pending {
        case .state(let slot, let existingId):
            uploadingStateSlots.insert(slot)
            Task {
                defer { uploadingStateSlots.remove(slot) }
                do {
                    guard let data = try saveStore.readState(romId: rom.id, slot: slot) else { return }
                    let thumbnail = try? saveStore.readThumbnail(romId: rom.id, slot: slot)
                    let fileName = "slot\(slot).state"
                    if update, let existingId {
                        let updated = try await updateStateUseCase.execute(id: existingId, emulator: nil, fileName: fileName, fileData: data, screenshotData: thumbnail)
                        if let idx = serverStates.firstIndex(where: { $0.id == updated.id }) { serverStates[idx] = updated }
                    } else {
                        let uploaded = try await uploadStateUseCase.execute(romId: rom.id, emulator: nil, fileName: fileName, fileData: data, screenshotData: thumbnail)
                        serverStates.append(uploaded)
                    }
                    recordManualSync()
                } catch {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        case .battery(let existingId):
            isUploadingBattery = true
            Task {
                defer { isUploadingBattery = false }
                do {
                    guard let data = try saveStore.readBattery(romId: rom.id) else { return }
                    let fileName = "\(rom.id).sav"
                    if update, let existingId {
                        let updated = try await updateSaveUseCase.execute(id: existingId, emulator: nil, fileName: fileName, fileData: data, screenshotData: nil)
                        if let idx = serverSaves.firstIndex(where: { $0.id == updated.id }) { serverSaves[idx] = updated }
                    } else {
                        let uploaded = try await uploadSaveUseCase.execute(romId: rom.id, emulator: nil, slot: nil, fileName: fileName, fileData: data, screenshotData: nil)
                        serverSaves.append(uploaded)
                    }
                    recordManualSync()
                } catch {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Helpers

    func slotFromFileName(_ name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("slot") else { return nil }
        return Int(stem.dropFirst("slot".count))
    }
}
