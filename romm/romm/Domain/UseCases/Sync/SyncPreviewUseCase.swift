import CryptoKit
import Foundation

protocol PSyncPreviewUseCase {
    /// Asks the server what a sync would do, without changing anything.
    func execute() async throws -> SyncPreview
}

/// Reports this device's battery saves to the server and returns the plan it
/// answers with.
///
/// Read-only as far as saves go: negotiation only compares content hashes and
/// timestamps, and nothing here acts on the result. It does open a sync session
/// server-side, which is the server's own bookkeeping and touches no save.
///
/// Deliberately battery only. Save states are held per slot index and their id
/// namespace overlaps with saves' over negotiation, which the existing
/// per-emulator sync works around with a separate path; pulling that in here
/// would mean reproducing the workaround before the screen shows anything.
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
        guard syncDevice.isSyncAPISupported else { throw SyncPreviewError.serverTooOld }
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

    /// Every battery save on this device, reported under the battery slot.
    ///
    /// The slot is what makes these saves pairable at all: the server never
    /// pairs a save that arrives without one. Uploads still send no slot today,
    /// so this preview shows what a sync *would* do once they do, which is the
    /// point of looking before changing it.
    private func collectBatterySaves() -> [ClientSaveState] {
        let romIds = (try? saveStore.listRomIds()) ?? []
        return romIds.compactMap { romId in
            guard let data = try? saveStore.readBattery(romId: romId), !data.isEmpty else { return nil }
            return ClientSaveState(
                romId: romId,
                fileName: "battery.sav",
                slot: SaveSlot.battery,
                // Attribution only; the server does not pair on it, and which
                // engine last wrote a save is not recorded per ROM.
                emulator: nil,
                contentHash: Self.contentHash(data),
                updatedAt: saveStore.batteryModifiedAt(romId: romId) ?? Date(timeIntervalSince1970: 0),
                fileSizeBytes: data.count
            )
        }
    }

    /// Drops state operations: this preview reports battery saves only, so an
    /// operation about a state came from another device and acting on it here
    /// would misrepresent what syncing from this screen does.
    private static func previewOperation(_ op: SyncOperationSchema) -> SyncPreviewOperation? {
        guard let romId = op.romId else { return nil }
        if op.fileName?.hasSuffix(".state") == true { return nil }

        let direction: SyncPreviewOperation.Direction
        switch op.action {
        case .upload: direction = .upload
        case .download: direction = .download
        case .conflict: direction = .conflict
        case .noOp: direction = .noOp
        // A newer server planned something this build has no name for. Showing
        // it as one of the four would misstate what syncing does, and this is a
        // preview the user is asked to approve, so it is left out.
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
