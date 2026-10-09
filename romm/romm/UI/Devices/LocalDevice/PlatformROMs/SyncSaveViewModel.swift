import Foundation
import Observation

/// Status over one ROM's sync, backed by the same negotiate-and-run logic the
/// sync overview uses: `syncThisGame()` re-negotiates and runs exactly the
/// way `SyncOverviewViewModel.syncNow()` does, just scoped to this ROM.
@Observable
@MainActor
final class SyncSaveViewModel {

    enum State {
        case idle
        case loading
        case loaded(SyncPreview)
        case failed(SyncPreviewError)
    }

    /// The battery save's status row, derived from the negotiated plan for
    /// this ROM. The plan can hold more than one battery operation (see
    /// `batteryStatus` below), so this is a verdict over all of them, not a
    /// single operation's direction.
    enum BatteryStatus: Equatable {
        case inSync
        case willUpload
        case willDownload
        case conflict
        case noSaveYet
    }

    let rom: DownloadedROM

    private(set) var state: State = .idle
    private(set) var statesStatus: StateSyncCoordinator.StateSyncStatus = .inSync
    private(set) var isSyncing = false
    private(set) var lastSyncReport: SaveSyncReport?
    private(set) var lastSyncMeta: SyncMetadata?
    var errorMessage: String?

    // Export
    var exportItem: ExportSaveItem?
    var isExportingServerSave = false
    private var exportTempURL: URL?

    private let previewUseCase: PSyncPreviewUseCase
    private let syncRunner: PSaveSyncRunner
    private let stateSyncCoordinator: StateSyncCoordinator
    private let listSavesUseCase: PListServerSavesUseCase
    private let downloadSaveUseCase: PDownloadSaveUseCase
    private let saveStore: PSaveStore
    private let syncDevice: PSyncDeviceRepository
    private let recordSyncUseCase: PRecordSyncUseCase
    private let getLastSyncUseCase: PGetLastSyncUseCase

    init(
        rom: DownloadedROM,
        previewUseCase: PSyncPreviewUseCase,
        syncRunner: PSaveSyncRunner,
        stateSyncCoordinator: StateSyncCoordinator,
        listSavesUseCase: PListServerSavesUseCase,
        downloadSaveUseCase: PDownloadSaveUseCase,
        saveStore: PSaveStore,
        syncDevice: PSyncDeviceRepository,
        recordSyncUseCase: PRecordSyncUseCase,
        getLastSyncUseCase: PGetLastSyncUseCase
    ) {
        self.rom = rom
        self.previewUseCase = previewUseCase
        self.syncRunner = syncRunner
        self.stateSyncCoordinator = stateSyncCoordinator
        self.listSavesUseCase = listSavesUseCase
        self.downloadSaveUseCase = downloadSaveUseCase
        self.saveStore = saveStore
        self.syncDevice = syncDevice
        self.recordSyncUseCase = recordSyncUseCase
        self.getLastSyncUseCase = getLastSyncUseCase
    }

    var preview: SyncPreview? {
        if case .loaded(let preview) = state { return preview }
        return nil
    }

    /// Whether "Sync This Game" has anything to try: a loaded plan with
    /// battery work, or states this ROM holds something out of sync for.
    var canSync: Bool {
        guard !isSyncing, let preview else { return false }
        if !preview.isUpToDate { return true }
        switch statesStatus {
        case .inSync, .unavailable: return false
        case .pending: return true
        }
    }

    var lastSyncSummary: String? { lastSyncReport?.summaryText }
    var lastSyncErrors: [String] { lastSyncReport?.cappedErrors ?? [] }

    /// Conflicts outrank downloads, which outrank uploads, the same precedence
    /// `SaveSyncStatus.init(preview:)` uses: a ROM can have more than one
    /// battery operation (rows with `slot == nil` ride alongside `battery`,
    /// and the server has no unique constraint on (rom_id, slot)), so picking
    /// just the first operation could hide a conflict behind an earlier upload.
    var batteryStatus: BatteryStatus? {
        guard let preview else { return nil }
        guard !preview.operations.isEmpty else { return .noSaveYet }
        if !preview.conflicts.isEmpty { return .conflict }
        if !preview.downloads.isEmpty { return .willDownload }
        if !preview.uploads.isEmpty { return .willUpload }
        return .inSync
    }

    // MARK: - Load

    func load() async {
        state = .loading
        errorMessage = nil
        _ = await negotiate()
        statesStatus = await stateSyncCoordinator.statusSummary(romId: rom.id)
        lastSyncMeta = getLastSyncUseCase.execute(romId: rom.id)
    }

    /// Mirrors `SyncOverviewViewModel.syncNow()`: negotiates a fresh plan
    /// right before running it, so acting never uses a plan that went stale
    /// while this screen sat open, then reloads to reflect the new state.
    func syncThisGame() async {
        guard canSync else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard let fresh = await negotiate() else { return }

        lastSyncReport = await syncRunner.run(preview: fresh, externalScans: [:], stateRomIds: [rom.id])
        recordSyncUseCase.execute(romId: rom.id, trigger: .manual)
        lastSyncMeta = SyncMetadata(date: Date(), trigger: .manual)
        await load()
    }

    private func negotiate() async -> SyncPreview? {
        do {
            let fresh = try await previewUseCase.execute(romIds: [rom.id])
            state = .loaded(fresh)
            return fresh
        } catch let error as SyncPreviewError {
            state = .failed(error)
        } catch {
            state = .failed(.negotiationFailed(error.localizedDescription))
        }
        return nil
    }

    // MARK: - Export

    /// Export local battery save via share sheet as .srm (RetroArch/libretro format).
    /// .srm and .sav are identical raw SRAM images — only the extension differs.
    func exportLocalBattery() {
        guard let data = try? saveStore.readBattery(romId: rom.id), !data.isEmpty else {
            errorMessage = "No local battery save found."
            return
        }
        presentExport(data: data, baseName: rom.name)
    }

    /// Downloads the server's battery save for this ROM and exports it via
    /// share sheet as .srm.
    func exportServerBattery() async {
        guard !isExportingServerSave else { return }
        isExportingServerSave = true
        defer { isExportingServerSave = false }
        do {
            guard let save = try await listSavesUseCase.execute(romId: rom.id).first else {
                errorMessage = "No server save found."
                return
            }
            if save.missingFromFs {
                errorMessage = "File missing on server — upload it again."
                return
            }
            let deviceId = await syncDevice.deviceId()
            let data = try await downloadSaveUseCase.execute(id: save.id, deviceId: deviceId, sessionId: nil)
            guard !data.isEmpty else { errorMessage = "Server returned empty file."; return }
            presentExport(data: data, baseName: save.fileNameNoExt)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func cleanupExportTemp() {
        if let url = exportTempURL {
            try? FileManager.default.removeItem(at: url)
            exportTempURL = nil
        }
        exportItem = nil
    }

    private func presentExport(data: Data, baseName: String) {
        cleanupExportTemp()
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let safeName = baseName
            .components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
        let fileURL = tmpDir.appendingPathComponent("\(safeName).srm")
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            exportTempURL = tmpDir
            exportItem = ExportSaveItem(url: fileURL)
        } catch {
            errorMessage = "Could not prepare export: \(error.localizedDescription)"
        }
    }
}

// MARK: - Export model

struct ExportSaveItem: Identifiable {
    let id = UUID()
    let url: URL
}
