import CryptoKit
import Foundation

protocol PSyncPreviewUseCase {
    /// Asks the server what a sync would do, without changing anything.
    ///
    /// - Parameter externalScans: What was found in other emulator apps'
    ///   folders. Passed in rather than scanned here, so scanning and
    ///   negotiating stay separate steps the caller composes.
    func execute(externalScans: [ExternalSaveScan]) async throws -> SyncPreview
}

/// Reports this device's battery saves to the server and returns the plan it
/// answers with.
///
/// Read-only as far as saves go: negotiation compares hashes and timestamps,
/// and nothing here acts on the result. It does open a sync session, which the
/// caller has to close once it has applied the plan or decided not to.
///
/// Battery only. Save states are held per slot index and their id namespace
/// overlaps with saves' over negotiation, which needs its own path.
final class SyncPreviewUseCase: PSyncPreviewUseCase {

    /// One local save as it was reported, kept beside the wire form so an
    /// operation coming back can be tied to the file it is about.
    private struct ReportedSave {
        let state: ClientSaveState
        let source: SyncSaveSource
        /// The file in another app's folder, nil for the internal store.
        let externalFile: ExternalSaveFile?
    }

    private let logger = Logger.sync
    private let saveStore: PSaveStore
    private let saveFiles: PExternalSaveFileRepository
    private let syncDevice: PSyncDeviceRepository
    private let apiClient: PRommAPIClient
    private let tokenProvider: PTokenProvider

    init(
        saveStore: PSaveStore,
        saveFiles: PExternalSaveFileRepository,
        syncDevice: PSyncDeviceRepository,
        apiClient: PRommAPIClient,
        tokenProvider: PTokenProvider
    ) {
        self.saveStore = saveStore
        self.saveFiles = saveFiles
        self.syncDevice = syncDevice
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
    }

    func execute(externalScans: [ExternalSaveScan]) async throws -> SyncPreview {
        guard tokenProvider.getServerURL() != nil else { throw SyncPreviewError.notConnected }
        switch await syncDevice.syncAPIAvailability() {
        case .available: break
        case .serverTooOld(let version): throw SyncPreviewError.serverTooOld(version: version)
        case .unknown: throw SyncPreviewError.serverVersionUnknown
        }
        guard let deviceId = await syncDevice.deviceId() else {
            throw SyncPreviewError.deviceRegistrationFailed
        }

        let reported = Self.deduplicated(collectBatterySaves() + collectExternalSaves(externalScans))
        logger.info("Sync preview: reporting \(reported.count) battery saves as device \(deviceId)")

        let response = try await negotiate(deviceId: deviceId, reported: reported)

        logger.info("Sync preview: \(response.operations.count) operations "
            + "(up=\(response.totalUpload ?? 0) down=\(response.totalDownload ?? 0) "
            + "conflict=\(response.totalConflict ?? 0) noop=\(response.totalNoOp ?? 0))")

        // Keyed on the pair the server pairs saves on, which is how an
        // operation finds the file it came from. Unique after deduplication.
        let bySlot = Dictionary(
            uniqueKeysWithValues: reported.map { (Self.slotKey(for: $0), $0) }
        )

        return SyncPreview(
            deviceId: deviceId,
            sessionId: response.sessionId,
            reportedSaveCount: reported.count,
            reportedCountsBySource: reported.reduce(into: [:]) { counts, save in
                counts[save.source, default: 0] += 1
            },
            operations: response.operations.compactMap { previewOperation($0, reported: bySlot) }
        )
    }

    // MARK: - Private

    /// The pair a save is paired on, server-side: `(rom_id, slot)`.
    private struct SlotKey: Hashable {
        let romId: Int
        let slot: String
    }

    private static func slotKey(for save: ReportedSave) -> SlotKey {
        SlotKey(romId: save.state.romId, slot: save.source.slot)
    }

    /// One save per `(rom_id, slot)`, keeping the most recently written.
    ///
    /// Needed because a single app's folder can hold more than one file that
    /// matches the same ROM: the layouts accept several battery extensions, so
    /// `Zelda.sav` and `Zelda.srm` both pair to the same slot. Reporting both
    /// would send the server two states for one pair, which it has no rule for.
    private static func deduplicated(_ saves: [ReportedSave]) -> [ReportedSave] {
        // Spelled out in steps rather than chained: the type checker gives up
        // on the one-expression form.
        let keyed: [(SlotKey, ReportedSave)] = saves.map { (slotKey(for: $0), $0) }
        let newest = Dictionary(keyed) { older, newer in
            newer.state.updatedAt > older.state.updatedAt ? newer : older
        }
        // Sorted so the reported order does not depend on dictionary hashing,
        // which would make the request differ between runs.
        let ordered = newest.sorted { lhs, rhs in
            lhs.key.romId == rhs.key.romId
                ? lhs.key.slot < rhs.key.slot
                : lhs.key.romId < rhs.key.romId
        }
        return ordered.map(\.value)
    }

    private func negotiate(
        deviceId: String,
        reported: [ReportedSave]
    ) async throws -> SyncNegotiateResponse {
        do {
            return try await apiClient.negotiateSync(
                SyncNegotiateRequest(deviceId: deviceId, saves: reported.map(\.state))
            )
        } catch {
            logger.warning("Sync preview failed: \(error.localizedDescription)")
            throw SyncPreviewError.negotiationFailed(error.localizedDescription)
        }
    }

    /// Every battery save in this app's own store, reported under the battery
    /// slot, without which the server pairs nothing.
    private func collectBatterySaves() -> [ReportedSave] {
        let romIds = (try? saveStore.listRomIds()) ?? []
        return romIds.compactMap { romId in
            guard let data = try? saveStore.readBattery(romId: romId), !data.isEmpty else { return nil }
            let state = ClientSaveState(
                romId: romId,
                fileName: SaveSlot.batteryFileName,
                slot: SaveSlot.battery,
                // Attribution only, and which engine wrote a save is not
                // recorded per ROM, so an invented value is worse than none.
                emulator: nil,
                contentHash: Self.contentHash(data),
                updatedAt: saveStore.batteryModifiedAt(romId: romId) ?? Date(timeIntervalSince1970: 0),
                fileSizeBytes: data.count
            )
            return ReportedSave(state: state, source: .internalStore, externalFile: nil)
        }
    }

    /// The saves other emulator apps wrote, each under its own slot.
    ///
    /// A slot per app rather than one shared battery slot: pairing keys on the
    /// slot alone, so two apps' saves for the same game in one slot would read
    /// as a single save changing back and forth.
    private func collectExternalSaves(_ scans: [ExternalSaveScan]) -> [ReportedSave] {
        scans.flatMap { scan -> [ReportedSave] in
            // The scan's URLs are only readable inside the folder's security
            // scope, so the contents come back from the repository, not from
            // reading the URL here.
            let contents = saveFiles.readSaves(at: scan.matched.map(\.url), for: scan.emulator)
            let source = SyncSaveSource.externalApp(scan.emulator)

            return scan.matched.compactMap { file in
                guard let data = contents[file.url], !data.isEmpty else { return nil }
                let state = ClientSaveState(
                    romId: file.romId,
                    fileName: file.fileName,
                    slot: source.slot,
                    emulator: scan.emulator.rawValue,
                    contentHash: Self.contentHash(data),
                    updatedAt: file.modifiedAt,
                    fileSizeBytes: data.count
                )
                return ReportedSave(state: state, source: source, externalFile: file)
            }
        }
    }

    /// Drops state operations: only battery saves are reported, so a state
    /// operation came from another device and is not this screen's to show.
    private func previewOperation(
        _ op: SyncOperationSchema,
        reported: [SlotKey: ReportedSave]
    ) -> SyncPreviewOperation? {
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

        // The slot says which app the save belongs to; a slot this build does
        // not own leaves the source nil, and applying skips it.
        let source = SyncSaveSource(slot: op.slot)
        let match = op.slot.flatMap { reported[SlotKey(romId: romId, slot: $0)] }

        return SyncPreviewOperation(
            romId: romId,
            direction: direction,
            saveId: op.saveId,
            serverFileName: op.fileName,
            slot: op.slot,
            emulator: op.emulator,
            reason: op.reason,
            serverUpdatedAt: op.serverUpdatedAt,
            source: source,
            externalFile: match?.externalFile,
            localUpdatedAt: match?.state.updatedAt
        )
    }

    /// Matches the hash the rest of the sync path sends, so the server compares
    /// like with like.
    private static func contentHash(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
