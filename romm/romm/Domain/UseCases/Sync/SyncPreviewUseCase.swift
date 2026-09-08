import CryptoKit
import Foundation

protocol PSyncPreviewUseCase {
    /// Asks the server what a sync would do, without changing anything.
    func execute() async throws -> SyncPreview
}

/// Reports this device's battery saves to the server and returns the plan it
/// answers with.
///
/// Read-only as far as saves go: negotiation compares hashes and timestamps,
/// and nothing here acts on the result. It does open a sync session, which is
/// the server's own bookkeeping and touches no save.
///
/// Battery only. Save states are held per slot index and their id namespace
/// overlaps with saves' over negotiation, which needs its own path.
final class SyncPreviewUseCase: PSyncPreviewUseCase {

    private let logger = Logger.sync
    private let saveStore: PSaveStore
    private let syncDevice: PSyncDeviceRepository
    private let apiClient: PRommAPIClient
    private let tokenProvider: PTokenProvider

    init(
        saveStore: PSaveStore,
        syncDevice: PSyncDeviceRepository,
        apiClient: PRommAPIClient,
        tokenProvider: PTokenProvider
    ) {
        self.saveStore = saveStore
        self.syncDevice = syncDevice
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func execute() async throws -> SyncPreview {
        guard tokenProvider.getServerURL() != nil else { throw SyncPreviewError.notConnected }
        switch await syncDevice.syncAPIAvailability() {
        case .available: break
        case .serverTooOld(let version): throw SyncPreviewError.serverTooOld(version: version)
        case .unknown: throw SyncPreviewError.serverVersionUnknown
        }
        guard let deviceId = await syncDevice.deviceId() else {
            throw SyncPreviewError.deviceRegistrationFailed
        }

        let localSaves = collectBatterySaves()
        logger.info("Sync preview: reporting \(localSaves.count) battery saves as device \(deviceId)")

        let response: SyncNegotiateResponse
        do {
            response = try await apiClient.negotiateSync(
                SyncNegotiateRequest(deviceId: deviceId, saves: localSaves)
            )
        } catch {
            logger.warning("Sync preview failed: \(error.localizedDescription)")
            throw SyncPreviewError.negotiationFailed(error.localizedDescription)
        }

        logger.info("Sync preview: \(response.operations.count) operations "
            + "(up=\(response.totalUpload ?? 0) down=\(response.totalDownload ?? 0) "
            + "conflict=\(response.totalConflict ?? 0) noop=\(response.totalNoOp ?? 0))")

        return SyncPreview(
            deviceId: deviceId,
            reportedSaveCount: localSaves.count,
            operations: response.operations.compactMap(Self.previewOperation)
        )
    }

    // MARK: - Private

    /// Every battery save on this device, reported under the battery slot,
    /// without which the server pairs nothing. Uploads still send no slot, so
    /// this shows what a sync *would* do once they do.
    private func collectBatterySaves() -> [ClientSaveState] {
        let romIds = (try? saveStore.listRomIds()) ?? []
        return romIds.compactMap { romId in
            guard let data = try? saveStore.readBattery(romId: romId), !data.isEmpty else { return nil }
            return ClientSaveState(
                romId: romId,
                fileName: "battery.sav",
                slot: SaveSlot.battery,
                // Attribution only, and which engine wrote a save is not
                // recorded per ROM, so an invented value is worse than none.
                emulator: nil,
                contentHash: Self.contentHash(data),
                updatedAt: saveStore.batteryModifiedAt(romId: romId) ?? Date(timeIntervalSince1970: 0),
                fileSizeBytes: data.count
            )
        }
    }

    /// Drops state operations: only battery saves are reported, so a state
    /// operation came from another device and is not this screen's to show.
    private static func previewOperation(_ op: SyncOperationSchema) -> SyncPreviewOperation? {
        guard let romId = op.romId else { return nil }
        if op.fileName?.hasSuffix(".state") == true { return nil }

        let direction: SyncPreviewOperation.Direction
        switch op.action {
        case .upload: direction = .upload
        case .download: direction = .download
        case .conflict: direction = .conflict
        case .noOp: direction = .noOp
        // A newer server planned something this build has no name for. Left
        // out rather than shown as one of the four, which would misstate it.
        case .unknown: return nil
        }

        return SyncPreviewOperation(
            romId: romId,
            direction: direction,
            serverFileName: op.fileName,
            slot: op.slot,
            emulator: op.emulator,
            reason: op.reason,
            serverUpdatedAt: op.serverUpdatedAt
        )
    }

    /// Matches the hash the rest of the sync path sends, so the server compares
    /// like with like.
    private static func contentHash(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
