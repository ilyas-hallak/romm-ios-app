import Foundation

/// The battery had nothing to carry out a resolution with. Should not happen
/// in practice (a conflict only shows once this device has its own changes),
/// kept as a guard rather than a silent no-op.
enum BatteryConflictResolutionError: Error, LocalizedError {
    case noLocalBattery
    case localBatteryIsBlank
    case noDeviceId

    var errorDescription: String? {
        switch self {
        case .noLocalBattery:
            return String(localized: "No local battery save to keep.")
        case .localBatteryIsBlank:
            return String(localized: "This device's save is blank and would overwrite the server's save with nothing.")
        case .noDeviceId:
            return String(localized: "This device could not be identified to the server. Reconnect and try again.")
        }
    }
}

@MainActor
protocol PBatteryConflictResolver {
    /// Backs up the local battery (unless blank), then downloads and writes
    /// the server's version in its place, and confirms the download so the
    /// next negotiate stops reporting the conflict.
    func keepServer(romId: Int, saveId: Int, serverUpdatedAt: Date?) async throws
    /// Downloads and backs up the server's version (unless blank), then
    /// uploads the local battery, overriding the server's conflict guard.
    func keepThisDevice(romId: Int, saveId: Int) async throws
}

/// Resolves a battery save conflict once the user has picked a winner for it.
///
/// Lives beside the other sync session services (`SaveSyncRunner`,
/// `CloudSaveSyncService`) rather than as a UseCase: it composes several Save
/// UseCases, and a UseCase may not call another one.
@MainActor
final class BatteryConflictResolver: PBatteryConflictResolver {
    private let logger = Logger.sync

    private let saveStore: PSaveStore
    private let uploadSaveUseCase: PUploadSaveUseCase
    private let downloadSaveUseCase: PDownloadSaveUseCase
    private let confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase
    private let syncDevice: PSyncDeviceRepository
    private let getDownloadedROMUseCase: PGetDownloadedROMUseCase

    init(
        saveStore: PSaveStore,
        uploadSaveUseCase: PUploadSaveUseCase,
        downloadSaveUseCase: PDownloadSaveUseCase,
        confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase,
        syncDevice: PSyncDeviceRepository,
        getDownloadedROMUseCase: PGetDownloadedROMUseCase
    ) {
        self.saveStore = saveStore
        self.uploadSaveUseCase = uploadSaveUseCase
        self.downloadSaveUseCase = downloadSaveUseCase
        self.confirmSaveDownloadUseCase = confirmSaveDownloadUseCase
        self.syncDevice = syncDevice
        self.getDownloadedROMUseCase = getDownloadedROMUseCase
    }

    func keepServer(romId: Int, saveId: Int, serverUpdatedAt: Date?) async throws {
        guard let deviceId = await syncDevice.deviceId() else {
            throw BatteryConflictResolutionError.noDeviceId
        }
        try backupLocalBatteryIfNeeded(romId: romId)

        let data = try await downloadSaveUseCase.execute(id: saveId, deviceId: deviceId, sessionId: nil)
        let platformSlug = try? getDownloadedROMUseCase.execute(romId: romId).rom.platformSlug
        let trimmed = GBABatteryFooter.trimmingRTCFooter(from: data, platformSlug: platformSlug)
        try saveStore.writeBattery(romId: romId, data: trimmed)
        if let serverUpdatedAt {
            try? saveStore.setBatteryModifiedAt(romId: romId, date: serverUpdatedAt)
        }
        do {
            _ = try await confirmSaveDownloadUseCase.execute(id: saveId, deviceId: deviceId)
        } catch {
            logger.warning("Download confirmation failed (save \(saveId)): \(error.localizedDescription)")
        }
        logger.info("Conflict resolved for ROM \(romId): kept server (save \(saveId))")
    }

    func keepThisDevice(romId: Int, saveId: Int) async throws {
        guard let deviceId = await syncDevice.deviceId() else {
            throw BatteryConflictResolutionError.noDeviceId
        }
        guard let local = try saveStore.readBattery(romId: romId) else {
            throw BatteryConflictResolutionError.noLocalBattery
        }
        guard !BatterySaveBlank.isBlank(local) else {
            throw BatteryConflictResolutionError.localBatteryIsBlank
        }

        // Downloaded and, when it holds anything, backed up before the local
        // save takes its place: once the upload below lands, this row's
        // current content is gone from the server's own history for this
        // slot (autocleanup may prune it).
        let serverData = try await downloadSaveUseCase.execute(id: saveId, deviceId: deviceId, sessionId: nil)
        if !BatterySaveBlank.isBlank(serverData) {
            try saveStore.backupBattery(romId: romId, data: serverData, origin: .server)
        }

        // A fresh POST rather than a PUT on the known row: the row only just
        // lost a conflict, meaning it moved since this device's baseline, so
        // replacing it in place would skip the very guard that caught that.
        // `overwrite` is safe here because the user just picked this device
        // as the winner; `autocleanup` keeps the discarded row as history
        // instead of deleting it outright.
        _ = try await uploadSaveUseCase.execute(
            romId: romId,
            emulator: nil,
            slot: SaveSlot.battery,
            deviceId: deviceId,
            sessionId: nil,
            autocleanup: true,
            overwrite: true,
            fileName: BatterySaveFileName.fallback(romId: romId),
            fileData: local,
            screenshotData: nil
        )
        logger.info("Conflict resolved for ROM \(romId): kept this device")
    }

    private func backupLocalBatteryIfNeeded(romId: Int) throws {
        guard let local = try saveStore.readBattery(romId: romId), !BatterySaveBlank.isBlank(local) else { return }
        try saveStore.backupBattery(romId: romId, data: local, origin: .local)
    }
}
