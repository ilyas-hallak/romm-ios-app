import Foundation

protocol PSyncPreviewUseCase {
    /// Asks the server what a sync would do, without changing anything.
    /// `romIds` scopes both the reported battery saves and the plan to those
    /// ROMs; `nil` reports every battery save this device holds.
    func execute(romIds: [Int]?) async throws -> SyncPreview
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

    func execute(romIds: [Int]?) async throws -> SyncPreview {
        guard tokenProvider.getServerURL() != nil else { throw SyncPreviewError.notConnected }
        switch await syncDevice.syncAPIAvailability() {
        case .available: break
        case .serverTooOld(let version): throw SyncPreviewError.serverTooOld(version: version)
        case .unknown: throw SyncPreviewError.serverVersionUnknown
        }
        guard let deviceId = await syncDevice.deviceId() else {
            throw SyncPreviewError.deviceRegistrationFailed
        }

        let localSaves = collectBatterySaves(romIds: romIds)
        logger.info("Sync preview: reporting \(localSaves.count) battery saves as device \(deviceId)")

        let negotiated: (response: SyncNegotiateResponse, deviceId: String)
        do {
            negotiated = try await negotiate(deviceId: deviceId, saves: localSaves, romIds: romIds)
        } catch let error as SyncPreviewError {
            throw error
        } catch {
            logger.warning("Sync preview failed: \(error.localizedDescription)")
            throw SyncPreviewError.negotiationFailed(error.localizedDescription)
        }
        let response = negotiated.response

        logger.info("Sync preview: \(response.operations.count) operations "
            + "(up=\(response.totalUpload ?? 0) down=\(response.totalDownload ?? 0) "
            + "conflict=\(response.totalConflict ?? 0) noop=\(response.totalNoOp ?? 0))")

        return SyncPreview(
            deviceId: negotiated.deviceId,
            reportedSaveCount: localSaves.count,
            operations: previewOperations(from: response.operations),
            sessionId: response.sessionId
        )
    }

    // MARK: - Private

    /// Negotiates, and registers again when the server does not know this
    /// device any more.
    ///
    /// The device id is stored once and kept, so a server that lost its device
    /// row (a reset database, a restored backup) answers every later negotiate
    /// with a 404 and sync stays broken for good. Registering again costs one
    /// request and is the only way back.
    private func negotiate(
        deviceId: String,
        saves: [ClientSaveState],
        romIds: [Int]?
    ) async throws -> (response: SyncNegotiateResponse, deviceId: String) {
        do {
            let response = try await apiClient.negotiateSync(
                SyncNegotiateRequest(deviceId: deviceId, saves: saves, romIds: romIds)
            )
            return (response, deviceId)
        } catch APIClientError.invalidResponse(404, let message) {
            logger.warning("Server does not know device \(deviceId) (\(message)), registering again")
            syncDevice.forgetDevice()
            guard let freshId = await syncDevice.deviceId(), freshId != deviceId else {
                throw SyncPreviewError.deviceRegistrationFailed
            }
            let response = try await apiClient.negotiateSync(
                SyncNegotiateRequest(deviceId: freshId, saves: saves, romIds: romIds)
            )
            return (response, freshId)
        }
    }

    /// Every battery save on this device, reported under the battery slot,
    /// without which the server pairs nothing. Scoped to `romIds` when given.
    private func collectBatterySaves(romIds: [Int]?) -> [ClientSaveState] {
        let allRomIds = (try? saveStore.listRomIds()) ?? []
        let scopedRomIds = romIds.map { allRomIds.filter($0.contains) } ?? allRomIds
        return scopedRomIds.compactMap { romId in
            guard let data = try? saveStore.readBattery(romId: romId), !data.isEmpty else { return nil }
            return ClientSaveState(
                romId: romId,
                fileName: BatterySaveFileName.fallback(romId: romId),
                slot: SaveSlot.battery,
                // Attribution only, and which engine wrote a save is not
                // recorded per ROM, so an invented value is worse than none.
                emulator: nil,
                contentHash: SaveContentHash.of(data),
                updatedAt: saveStore.batteryModifiedAt(romId: romId) ?? Date(timeIntervalSince1970: 0),
                fileSizeBytes: data.count
            )
        }
    }

    /// Maps the raw operations to what this screen shows, applying the one
    /// rule that needs more than a single row: a download can come from any
    /// non-null slot (a web upload lands under "autosave", a different client
    /// under "default", ...), so a ROM with several such rows must still only
    /// ever offer one download, the newest. Every other direction stays
    /// battery-slot-only, since this device only ever reports that slot and
    /// anything else is another device's save, not this one's to show.
    ///
    /// A download candidate is only shown when it would really be applied.
    /// Negotiate reports a `download` for every foreign-slot row of a ROM
    /// until that exact row is confirmed, including ones that are older than
    /// the local battery or byte-identical to it; nothing ever downloads
    /// those, so showing them made such a game look permanently "pending
    /// download" (issue #208 follow-up). Filtered with the same
    /// `BatteryDownloadDecision` the pre-launch pull and the manual sync
    /// runner apply, so all three paths agree on what counts as a real
    /// download.
    private func previewOperations(from operations: [SyncOperationSchema]) -> [SyncPreviewOperation] {
        let eligible = operations.filter { $0.romId != nil && $0.fileName?.hasSuffix(".state") != true }
        let byRomId = Dictionary(grouping: eligible, by: { $0.romId ?? 0 })

        return byRomId.flatMap { romId, opsForRom -> [SyncPreviewOperation] in
            let download = qualifyingDownload(romId: romId, in: opsForRom)

            // A download that qualifies above is, by definition, newer than
            // the local battery (or the local file is blank/missing) -
            // exactly what makes the pre-launch pull download rather than
            // push. So when a ROM has both a qualifying download and a
            // battery upload op, only the download is kept; pushing the
            // local file at the same time would just be undone by the next
            // pull.
            if let download { return [download] }

            return opsForRom
                .filter { $0.action != .download }
                .filter { $0.slot == nil || $0.slot == SaveSlot.battery }
                .compactMap(Self.previewOperation)
        }
    }

    /// The newest download candidate for this ROM that would actually be
    /// applied: a non-null slot, genuinely newer than (or the local battery
    /// is missing/blank compared to) the local file, and not already
    /// byte-identical to it.
    private func qualifyingDownload(romId: Int, in opsForRom: [SyncOperationSchema]) -> SyncPreviewOperation? {
        // Null-slot rows are archival (pre-slot servers, or rows negotiate
        // already excludes from pairing) and never a download candidate.
        let candidates = opsForRom.filter { $0.action == .download && $0.slot != nil }
        guard !candidates.isEmpty else { return nil }

        let localData = (try? saveStore.readBattery(romId: romId)).flatMap { $0 }
        let localModifiedAt = saveStore.batteryModifiedAt(romId: romId)
        let localIsBlank = localData.map(BatterySaveBlank.isBlank) ?? true
        let localHash = localData.map(SaveContentHash.of)

        let qualifying = candidates.filter { op in
            let sameContent = op.serverContentHash != nil && op.serverContentHash == localHash
            guard !sameContent else { return false }
            return BatteryDownloadDecision.shouldApply(
                candidateUpdatedAt: op.serverUpdatedAt, localModifiedAt: localModifiedAt, localIsBlank: localIsBlank
            )
        }
        return BatteryDownloadPicker.pickNewest(qualifying, updatedAt: { $0.serverUpdatedAt }).flatMap(Self.previewOperation)
    }

    private static func previewOperation(_ op: SyncOperationSchema) -> SyncPreviewOperation? {
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

        guard let romId = op.romId else { return nil }
        return SyncPreviewOperation(
            romId: romId,
            direction: direction,
            serverFileName: op.fileName,
            slot: op.slot,
            emulator: op.emulator,
            reason: op.reason,
            serverUpdatedAt: op.serverUpdatedAt,
            saveId: op.saveId,
            serverContentHash: op.serverContentHash
        )
    }
}
