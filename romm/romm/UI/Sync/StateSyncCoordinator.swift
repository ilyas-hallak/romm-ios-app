import Foundation

/// Syncs one ROM's save states against the server, one slot at a time,
/// through `StateSyncDecision` so `CloudSaveSyncService`'s pre-launch pull and
/// `SaveSyncRunner`'s manual, bidirectional sync never grow different ideas of
/// what counts as "changed" for a slot the last push never reached the server.
///
/// Not a UseCase: it composes several of them, and a UseCase may not call
/// another one. Lives at the same Session/UI-sync layer as the two callers.
final class StateSyncCoordinator {
    enum Mode {
        /// Before-launch pull: never uploads, only ever brings local state up
        /// to date from the server.
        case pullOnly
        /// Manual sync: both directions.
        case bidirectional
    }

    enum SlotOutcome {
        case uploaded
        case downloaded
        case skipped
        /// Content was identical on both sides; only the baseline was
        /// refreshed, nothing was transferred.
        case recordedBaseline
        case failed(String)
    }

    private let logger = Logger.sync
    private let saveStore: PSaveStore
    private let listStatesUseCase: PListServerStatesUseCase
    private let uploadStateUseCase: PUploadStateUseCase
    private let updateStateUseCase: PUpdateStateUseCase
    private let downloadStateUseCase: PDownloadStateUseCase

    init(
        saveStore: PSaveStore,
        listStatesUseCase: PListServerStatesUseCase,
        uploadStateUseCase: PUploadStateUseCase,
        updateStateUseCase: PUpdateStateUseCase,
        downloadStateUseCase: PDownloadStateUseCase
    ) {
        self.saveStore = saveStore
        self.listStatesUseCase = listStatesUseCase
        self.uploadStateUseCase = uploadStateUseCase
        self.updateStateUseCase = updateStateUseCase
        self.downloadStateUseCase = downloadStateUseCase
    }

    /// Syncs every slot this device or the server holds something for, for one ROM.
    func syncStates(romId: Int, mode: Mode) async -> [SlotOutcome] {
        let localEntries = (try? saveStore.listStates(romId: romId)) ?? []
        let localSlots = Set(localEntries.map(\.slot))

        let serverStates: [StateSchema]
        do {
            serverStates = try await listStatesUseCase.execute(romId: romId)
        } catch {
            guard !localSlots.isEmpty else { return [] }
            return [.failed("ROM \(romId): could not list server states (\(error.localizedDescription))")]
        }

        let serverBySlot = Self.assignSlots(serverStates, warnOnOverflow: logger)
        let slots = localSlots.union(serverBySlot.keys)

        var outcomes: [SlotOutcome] = []
        for slot in slots {
            outcomes.append(await syncSlot(romId: romId, slot: slot, server: serverBySlot[slot], mode: mode, emulator: nil))
        }
        return outcomes
    }

    /// Syncs a single slot right after a local save. The state (and, when
    /// captured, its thumbnail) is already written to disk by the caller
    /// before this runs, so this re-reads from disk rather than taking the
    /// bytes as a parameter, keeping this on the same path `syncStates` uses.
    func syncSlot(romId: Int, slot: Int, emulator: String?) async -> SlotOutcome {
        let states: [StateSchema]
        do {
            states = try await listStatesUseCase.execute(romId: romId)
        } catch {
            // Treating this as "server has nothing" would upload a second row.
            return .failed("ROM \(romId) slot \(slot): could not list server states (\(error.localizedDescription))")
        }
        let server = Self.assignSlots(states, warnOnOverflow: logger)[slot]
        return await syncSlot(romId: romId, slot: slot, server: server, mode: .bidirectional, emulator: emulator)
    }

    private static func assignSlots(_ states: [StateSchema], warnOnOverflow logger: Logger) -> [Int: StateSchema] {
        let (slotByStateId, overflow) = StateSlots.assign(states.map {
            StateSlots.Candidate(id: $0.id, fileName: $0.fileName, updatedAt: $0.updatedAt)
        })
        if overflow > 0 {
            logger.warning("\(overflow) server state(s) skipped: no free slot (max 21)")
        }
        var bySlot: [Int: StateSchema] = [:]
        for state in states {
            guard let slot = slotByStateId[state.id] else { continue }
            bySlot[slot] = state
        }
        return bySlot
    }

    private func syncSlot(romId: Int, slot: Int, server: StateSchema?, mode: Mode, emulator: String?) async -> SlotOutcome {
        let localData = try? saveStore.readState(romId: romId, slot: slot)
        let local: StateSyncDecision.LocalInfo? = localData.flatMap { data in
            saveStore.stateModifiedAt(romId: romId, slot: slot).map {
                StateSyncDecision.LocalInfo(modifiedAt: $0, contentHash: SaveContentHash.of(data))
            }
        }
        let baseline = try? saveStore.readStateBaseline(romId: romId, slot: slot)
        let serverInfo = server.map {
            StateSyncDecision.ServerInfo(id: $0.id, updatedAt: $0.updatedAt, fileName: $0.fileName)
        }

        switch StateSyncDecision.decideFirstStep(local: local, server: serverInfo, baseline: baseline ?? nil) {
        case .nothing:
            return .skipped
        case .upload:
            guard mode == .bidirectional else { return .skipped }
            return await uploadOverServerRow(romId: romId, slot: slot, server: server, emulator: emulator)
        case .download:
            guard let server else { return .skipped }
            return await download(romId: romId, slot: slot, server: server)
        case .needsServerContent:
            guard let server, let local else { return .skipped }
            return await resolveWithServerContent(
                romId: romId, slot: slot, local: local, server: server,
                baseline: baseline ?? nil, mode: mode, emulator: emulator
            )
        }
    }

    private func resolveWithServerContent(
        romId: Int, slot: Int,
        local: StateSyncDecision.LocalInfo,
        server: StateSchema,
        baseline: StateSyncBaseline?,
        mode: Mode,
        emulator: String?
    ) async -> SlotOutcome {
        let serverData: Data
        do {
            serverData = try await downloadStateUseCase.execute(id: server.id)
        } catch {
            return .failed("ROM \(romId) slot \(slot): could not fetch server state to compare (\(error.localizedDescription))")
        }
        let serverHash = SaveContentHash.of(serverData)
        let serverInfo = StateSyncDecision.ServerInfo(id: server.id, updatedAt: server.updatedAt, fileName: server.fileName)
        let secondStep = StateSyncDecision.decideSecondStep(
            local: local, server: serverInfo, baseline: baseline, serverContentHash: serverHash
        )

        switch secondStep {
        case .nothing:
            return .skipped
        case .recordBaselineOnly:
            recordBaseline(romId: romId, slot: slot, server: server, contentHash: serverHash)
            return .recordedBaseline
        case .upload:
            guard mode == .bidirectional else { return .skipped }
            return await uploadOverServerRow(romId: romId, slot: slot, server: server, emulator: emulator)
        case .download:
            return await applyDownload(romId: romId, slot: slot, server: server, data: serverData)
        }
    }

    private func uploadOverServerRow(romId: Int, slot: Int, server: StateSchema?, emulator: String?) async -> SlotOutcome {
        guard let server else {
            return await upload(romId: romId, slot: slot, existing: nil, emulator: emulator)
        }
        // `StateSlots.assign` parks a state without a slot name under a
        // synthetic slot whose number shifts as other such states come and
        // go, so only a row whose own name says this slot is overwritten.
        guard StateSlots.slot(fromFileName: server.fileName) == slot else { return .skipped }
        return await upload(romId: romId, slot: slot, existing: server, emulator: emulator)
    }

    private func upload(romId: Int, slot: Int, existing: StateSchema?, emulator: String?) async -> SlotOutcome {
        guard let data = try? saveStore.readState(romId: romId, slot: slot), !data.isEmpty else {
            return .failed("ROM \(romId) slot \(slot): no local state to upload")
        }
        let thumbnail = try? saveStore.readThumbnail(romId: romId, slot: slot)
        let fileName = StateSlots.fileName(slot: slot)
        do {
            let result: StateSchema
            if let existing {
                result = try await updateStateUseCase.execute(
                    id: existing.id, emulator: emulator, fileName: fileName, fileData: data, screenshotData: thumbnail
                )
            } else {
                result = try await uploadStateUseCase.execute(
                    romId: romId, emulator: emulator, fileName: fileName, fileData: data, screenshotData: thumbnail
                )
            }
            recordBaseline(romId: romId, slot: slot, server: result, contentHash: SaveContentHash.of(data))
        } catch {
            return .failed("ROM \(romId) slot \(slot): state upload failed (\(error.localizedDescription))")
        }
        return .uploaded
    }

    private func download(romId: Int, slot: Int, server: StateSchema) async -> SlotOutcome {
        do {
            let data = try await downloadStateUseCase.execute(id: server.id)
            return await applyDownload(romId: romId, slot: slot, server: server, data: data)
        } catch {
            return .failed("ROM \(romId) slot \(slot): state download failed (\(error.localizedDescription))")
        }
    }

    private func applyDownload(romId: Int, slot: Int, server: StateSchema, data: Data) async -> SlotOutcome {
        do {
            try? saveStore.backupSlotForUndoSave(romId: romId, slot: slot)
            try saveStore.writeState(romId: romId, slot: slot, data: data)
            try? saveStore.setStateModifiedAt(romId: romId, slot: slot, date: server.updatedAt)
            // No authenticated way to fetch a screenshot's bytes exists today
            // (only Kingfisher's unauthenticated, URL-based image loading), so
            // a stale thumbnail from the overwritten content is dropped
            // rather than left showing the wrong picture.
            try? saveStore.deleteThumbnail(romId: romId, slot: slot)
            recordBaseline(romId: romId, slot: slot, server: server, contentHash: SaveContentHash.of(data))
        } catch {
            return .failed("ROM \(romId) slot \(slot): state download failed (\(error.localizedDescription))")
        }
        return .downloaded
    }

    private func recordBaseline(romId: Int, slot: Int, server: StateSchema, contentHash: String) {
        let baseline = StateSyncBaseline(serverId: server.id, serverUpdatedAt: server.updatedAt, contentHash: contentHash)
        try? saveStore.writeStateBaseline(romId: romId, slot: slot, baseline: baseline)
    }
}
