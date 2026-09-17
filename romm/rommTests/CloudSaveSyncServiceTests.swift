import Testing
import Foundation
@testable import romm

// MARK: - Fakes

private final class FakeCloudSaveSyncSettings: PCloudSaveSyncSettings, @unchecked Sendable {
    var isEnabled: Bool
    init(isEnabled: Bool = true) { self.isEnabled = isEnabled }
}

private final class FakeRecordSyncUseCase: PRecordSyncUseCase, @unchecked Sendable {
    private(set) var calls: [(romId: Int, trigger: SyncTrigger)] = []
    func execute(romId: Int, trigger: SyncTrigger) {
        calls.append((romId, trigger))
    }
}

private final class FakeSyncDeviceRepository: PSyncDeviceRepository, @unchecked Sendable {
    var deviceIdToReturn: String?
    func syncAPIAvailability() async -> SyncAPIAvailability { .available }
    func deviceId() async -> String? { deviceIdToReturn }
    func completeSyncSession(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {}
}

/// Fails negotiate outright, so `pullBeforeLaunch` falls back to the legacy
/// list-based battery pull. `StubRommAPIClient` traps on every unstubbed
/// call, so only what a scenario needs is ever overridden.
private final class NegotiateFailingAPIClient: StubRommAPIClient, @unchecked Sendable {
    override func negotiateSync(_ body: SyncNegotiateRequest) async throws -> SyncNegotiateResponse {
        throw URLError(.badServerResponse)
    }
}

/// Succeeds negotiate with a canned response, so `pullBeforeLaunch` takes the
/// negotiated path instead of falling back to the legacy pull.
private final class NegotiateStubAPIClient: StubRommAPIClient, @unchecked Sendable {
    let response: SyncNegotiateResponse
    init(response: SyncNegotiateResponse) { self.response = response }
    override func negotiateSync(_ body: SyncNegotiateRequest) async throws -> SyncNegotiateResponse {
        response
    }
}

/// `SyncNegotiateResponse`/`SyncOperationSchema` only expose a decoding
/// initialiser (mirroring the server's actual response shape), so a canned
/// response has to go through the decoder rather than a memberwise init.
private func makeNegotiateResponse(operations: [[String: Any]]) -> SyncNegotiateResponse {
    let payload: [String: Any] = [
        "session_id": 1,
        "operations": operations,
        "total_upload": 0,
        "total_download": 0,
        "total_conflict": 0,
        "total_no_op": operations.count
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return try! JSONDecoder().decode(SyncNegotiateResponse.self, from: data)
}

private func negotiateOperationJSON(
    action: SyncAction, romId: Int, fileName: String, saveId: Int? = nil, slot: String? = nil,
    serverUpdatedAt: Date? = nil
) -> [String: Any] {
    var json: [String: Any] = ["action": action.rawValue, "rom_id": romId, "file_name": fileName]
    if let saveId { json["save_id"] = saveId }
    if let slot { json["slot"] = slot }
    if let serverUpdatedAt { json["server_updated_at"] = ISO8601DateFormatter().string(from: serverUpdatedAt) }
    return json
}

private final class FakeListServerSavesUseCase: PListServerSavesUseCase, @unchecked Sendable {
    var savesByRomId: [Int: [SaveSchema]] = [:]
    var error: Error?
    private(set) var requestedRomIds: [Int] = []

    func execute(romId: Int) async throws -> [SaveSchema] {
        requestedRomIds.append(romId)
        if let error { throw error }
        return savesByRomId[romId] ?? []
    }

    static func makeSchema(id: Int, romId: Int, fileName: String, updatedAt: Date = Date()) -> SaveSchema {
        SaveSchema(
            id: id, romId: romId, userId: 1, fileName: fileName, fileNameNoTags: fileName,
            fileNameNoExt: fileName, fileExtension: "sav", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: updatedAt,
            updatedAt: updatedAt, emulator: nil, screenshot: nil
        )
    }
}

private final class FakeUploadSaveUseCase: PUploadSaveUseCase, @unchecked Sendable {
    var error: Error?
    private(set) var calls: [(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, overwrite: Bool?, fileName: String, fileData: Data)] = []
    private var nextId = 500

    func execute(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, overwrite: Bool?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        if let error { throw error }
        calls.append((romId, emulator, slot, deviceId, sessionId, autocleanup, overwrite, fileName, fileData))
        nextId += 1
        return FakeListServerSavesUseCase.makeSchema(id: nextId, romId: romId, fileName: fileName)
    }
}

private final class FakeUpdateSaveUseCase: PUpdateSaveUseCase, @unchecked Sendable {
    var error: Error?
    private(set) var calls: [(id: Int, emulator: String?, fileName: String, fileData: Data)] = []

    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        if let error { throw error }
        calls.append((id, emulator, fileName, fileData))
        return FakeListServerSavesUseCase.makeSchema(id: id, romId: 0, fileName: fileName)
    }
}

private final class FakeDownloadSaveUseCase: PDownloadSaveUseCase, @unchecked Sendable {
    var dataForId: [Int: Data] = [:]
    private(set) var calls: [(id: Int, deviceId: String?, sessionId: String?)] = []

    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data {
        calls.append((id, deviceId, sessionId))
        guard let data = dataForId[id] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

private final class FakeConfirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase, @unchecked Sendable {
    var error: Error?
    private(set) var calls: [(id: Int, deviceId: String)] = []

    func execute(id: Int, deviceId: String) async throws -> SaveSchema {
        calls.append((id, deviceId))
        if let error { throw error }
        return FakeListServerSavesUseCase.makeSchema(id: id, romId: 0, fileName: "battery.sav")
    }
}

private final class FakeListServerStatesUseCase: PListServerStatesUseCase, @unchecked Sendable {
    var statesByRomId: [Int: [StateSchema]] = [:]

    func execute(romId: Int) async throws -> [StateSchema] {
        statesByRomId[romId] ?? []
    }

    static func makeSchema(id: Int, romId: Int, fileName: String, updatedAt: Date) -> StateSchema {
        StateSchema(
            id: id, romId: romId, userId: 1, fileName: fileName, fileNameNoTags: fileName,
            fileNameNoExt: fileName, fileExtension: "state", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: updatedAt,
            updatedAt: updatedAt, emulator: nil, screenshot: nil
        )
    }
}

private final class FakeDownloadStateUseCase: PDownloadStateUseCase, @unchecked Sendable {
    var dataForId: [Int: Data] = [:]
    private(set) var requestedIds: [Int] = []

    func execute(id: Int) async throws -> Data {
        requestedIds.append(id)
        guard let data = dataForId[id] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

/// Neither is exercised by any scenario here: state pushing is not under
/// test. Trapping loudly on a call would fail the responsible test fast
/// rather than silently accepting an unplanned state upload.
private final class UnusedUploadStateUseCase: PUploadStateUseCase, @unchecked Sendable {
    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}

private final class UnusedUpdateStateUseCase: PUpdateStateUseCase, @unchecked Sendable {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}

// MARK: - Tests

@MainActor
struct CloudSaveSyncServiceTests {

    private func makeStore() -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSaveSyncServiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return LocalSaveStoreRepository(rootDirectory: tmp)
    }

    private func makeConfig(romId: Int = 1, emulator: String = "delta-ios", batteryFileName: String = "battery.sav") -> CloudSaveSyncService.Config {
        .init(romId: romId, emulator: emulator, batteryFileName: batteryFileName)
    }

    private struct Fakes {
        let listSaves = FakeListServerSavesUseCase()
        let uploadSave = FakeUploadSaveUseCase()
        let updateSave = FakeUpdateSaveUseCase()
        let downloadSave = FakeDownloadSaveUseCase()
        let confirmDownload = FakeConfirmSaveDownloadUseCase()
        let listStates = FakeListServerStatesUseCase()
        let downloadState = FakeDownloadStateUseCase()
        let recordSync = FakeRecordSyncUseCase()
        let syncDevice = FakeSyncDeviceRepository()
    }

    private func makeService(
        store: PSaveStore,
        fakes: Fakes,
        config: CloudSaveSyncService.Config,
        settings: FakeCloudSaveSyncSettings = FakeCloudSaveSyncSettings(),
        apiClient: PRommAPIClient = NegotiateFailingAPIClient()
    ) -> CloudSaveSyncService {
        CloudSaveSyncService(
            config: config,
            saveStore: store,
            listSavesUseCase: fakes.listSaves,
            uploadSaveUseCase: fakes.uploadSave,
            updateSaveUseCase: fakes.updateSave,
            downloadSaveUseCase: fakes.downloadSave,
            confirmSaveDownloadUseCase: fakes.confirmDownload,
            listStatesUseCase: fakes.listStates,
            uploadStateUseCase: UnusedUploadStateUseCase(),
            updateStateUseCase: UnusedUpdateStateUseCase(),
            downloadStateUseCase: fakes.downloadState,
            settings: settings,
            recordSyncUseCase: fakes.recordSync,
            apiClient: apiClient,
            syncDevice: fakes.syncDevice
        )
    }

    // MARK: - Pull battery + download confirmation

    /// After a downloaded battery save is written locally, the server is told
    /// this device now has it, so the next negotiate stops replanning the
    /// same download.
    @Test func downloadedBatterySaveConfirmsToServer() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.listSaves.savesByRomId[1] = [
            FakeListServerSavesUseCase.makeSchema(id: 42, romId: 1, fileName: "battery.sav", updatedAt: serverTime)
        ]
        fakes.downloadSave.dataForId[42] = Data([0x01, 0x02])

        let service = makeService(store: store, fakes: fakes, config: makeConfig())
        await service.pullBeforeLaunch()

        #expect(try store.readBattery(romId: 1) == Data([0x01, 0x02]))
        #expect(fakes.confirmDownload.calls.count == 1)
        #expect(fakes.confirmDownload.calls.first?.id == 42)
        #expect(fakes.confirmDownload.calls.first?.deviceId == "device-1")
    }

    /// The confirmation is best effort: a failure there must not undo the
    /// download that already succeeded and was already written to disk.
    @Test func failedConfirmationStillLeavesTheDownloadedSaveInPlace() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.listSaves.savesByRomId[1] = [
            FakeListServerSavesUseCase.makeSchema(id: 42, romId: 1, fileName: "battery.sav", updatedAt: serverTime)
        ]
        fakes.downloadSave.dataForId[42] = Data([0x01, 0x02])
        fakes.confirmDownload.error = URLError(.notConnectedToInternet)

        let service = makeService(store: store, fakes: fakes, config: makeConfig())
        await service.pullBeforeLaunch()

        #expect(try store.readBattery(romId: 1) == Data([0x01, 0x02]))
        #expect(fakes.confirmDownload.calls.count == 1)
    }

    // MARK: - Pull states (basic case)

    @Test func pullStatesDownloadsANewerServerState() async throws {
        let store = makeStore()
        let fakes = Fakes()
        // No registered device at all: negotiate is skipped outright and the
        // legacy pull takes over for both battery (no-op, no server save) and
        // states.
        fakes.syncDevice.deviceIdToReturn = nil
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.listStates.statesByRomId[1] = [
            FakeListServerStatesUseCase.makeSchema(id: 30, romId: 1, fileName: "slot0.state", updatedAt: serverTime)
        ]
        fakes.downloadState.dataForId[30] = Data([0x10, 0x20])

        let service = makeService(store: store, fakes: fakes, config: makeConfig())
        await service.pullBeforeLaunch()

        #expect(try store.readState(romId: 1, slot: 0) == Data([0x10, 0x20]))
        #expect(fakes.downloadState.requestedIds == [30])
    }

    // MARK: - Push battery

    /// Every push carries this device's id, the fixed `battery` slot, and
    /// `autocleanup=true`; the server dedups and prunes now, not the client.
    @Test func pushSendsSlotDeviceIdAndAutocleanup() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-9"

        let service = makeService(store: store, fakes: fakes, config: makeConfig())
        await service.pushBatteryAsync(data: Data([0xAA]))

        #expect(fakes.uploadSave.calls.count == 1)
        #expect(fakes.uploadSave.calls.first?.slot == SaveSlot.battery)
        #expect(fakes.uploadSave.calls.first?.deviceId == "device-9")
        #expect(fakes.uploadSave.calls.first?.autocleanup == true)
        // Nothing here established that this device wins, so the server's
        // conflict guard has to stay on: no `overwrite` at all.
        #expect(fakes.uploadSave.calls.first?.overwrite == nil)
    }

    /// HTTP 409 means the slot moved on the server since this device's last
    /// sync. It must be caught, not surfaced as a hard failure.
    @Test func pushConflictIsCaughtNotThrown() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        fakes.uploadSave.error = APIClientError.conflict("slot moved")

        let service = makeService(store: store, fakes: fakes, config: makeConfig())
        // Reaching this point without the `await` throwing already proves the
        // conflict was caught internally, not just its usual side effects.
        await service.pushBatteryAsync(data: Data([0xAA]))

        #expect(fakes.recordSync.calls.isEmpty)
    }

    /// Replacing a row in place has no conflict guard of its own, so a push
    /// may only do it while the server row is still the one this session
    /// pulled.
    @Test func pushUpdatesInPlaceWhileTheServerRowIsUnchanged() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let (service, _) = await makeServiceAfterPull(id: 42, fakes: fakes, store: store)

        await service.pushBatteryAsync(data: Data([0xAA]))

        #expect(fakes.updateSave.calls.count == 1)
        #expect(fakes.updateSave.calls.first?.id == 42)
        #expect(fakes.uploadSave.calls.isEmpty)
    }

    /// A play session can run for hours. If another device wrote that row in
    /// the meantime, the push has to leave it alone instead of silently
    /// replacing a save this device never saw.
    @Test func pushLeavesTheRowAloneWhenAnotherDeviceWroteIt() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let (service, pulledAt) = await makeServiceAfterPull(id: 42, fakes: fakes, store: store)
        fakes.listSaves.savesByRomId[1] = [
            FakeListServerSavesUseCase.makeSchema(
                id: 42, romId: 1, fileName: "battery.sav", updatedAt: pulledAt.addingTimeInterval(60)
            )
        ]

        await service.pushBatteryAsync(data: Data([0xAA]))

        #expect(fakes.updateSave.calls.isEmpty)
        #expect(fakes.uploadSave.calls.isEmpty)
    }

    /// The row can also be gone, deleted or pruned by autocleanup. Then there
    /// is nothing to replace and a fresh, guarded upload is the right move.
    @Test func pushUploadsAFreshRowWhenTheKnownOneIsGone() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let (service, _) = await makeServiceAfterPull(id: 42, fakes: fakes, store: store)
        fakes.listSaves.savesByRomId[1] = []

        await service.pushBatteryAsync(data: Data([0xAA]))

        #expect(fakes.updateSave.calls.isEmpty)
        #expect(fakes.uploadSave.calls.count == 1)
        #expect(fakes.uploadSave.calls.first?.overwrite == nil)
    }

    /// Unverifiable is treated like moved: without an answer from the server
    /// there is no way to tell a safe replace from a clobber.
    @Test func pushLeavesTheRowAloneWhenTheServerCannotBeChecked() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let (service, _) = await makeServiceAfterPull(id: 42, fakes: fakes, store: store)
        fakes.listSaves.error = APIClientError.invalidResponse(500, "offline")

        await service.pushBatteryAsync(data: Data([0xAA]))

        #expect(fakes.updateSave.calls.isEmpty)
        #expect(fakes.uploadSave.calls.isEmpty)
    }

    /// A service in the state a launch leaves it in: it knows the server's
    /// battery row and when that row was last written. The timestamp comes
    /// back with it, so a test can move the row forward from it.
    private func makeServiceAfterPull(
        id: Int, fakes: Fakes, store: PSaveStore
    ) async -> (service: CloudSaveSyncService, pulledAt: Date) {
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.syncDevice.deviceIdToReturn = "device-1"
        fakes.listSaves.savesByRomId[1] = [
            FakeListServerSavesUseCase.makeSchema(id: id, romId: 1, fileName: "battery.sav", updatedAt: serverTime)
        ]
        fakes.downloadSave.dataForId[id] = Data([0x01])

        let service = makeService(store: store, fakes: fakes, config: makeConfig())
        await service.pullBeforeLaunch()
        return (service, serverTime)
    }

    /// `pushBattery` is the fire-and-forget entry point production code
    /// calls; disabled sync must still short-circuit before any work starts.
    @Test func pushBatteryDoesNothingWhenSyncIsDisabled() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let settings = FakeCloudSaveSyncSettings(isEnabled: false)
        let service = makeService(store: store, fakes: fakes, config: makeConfig(), settings: settings)

        service.pushBattery(data: Data([0xAA]))

        #expect(fakes.uploadSave.calls.isEmpty)
    }

    // MARK: - serverBatteryId adopted from every negotiate operation

    /// `serverBatteryId` must be learned from every negotiate operation that
    /// names this ROM's battery file, not only from a `download` action: a
    /// `noOp` verdict still names the row the server already holds, and the
    /// next push has to update it in place instead of creating a duplicate.
    @Test func serverBatteryIdAdoptedFromANoOpNegotiateOperation() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        let response = makeNegotiateResponse(operations: [
            negotiateOperationJSON(action: .noOp, romId: 1, fileName: "battery.sav", saveId: 77)
        ])
        let client = NegotiateStubAPIClient(response: response)

        let service = makeService(store: store, fakes: fakes, config: makeConfig(), apiClient: client)
        await service.pullBeforeLaunch()

        // A no_op plans nothing to fetch.
        #expect(fakes.downloadSave.calls.isEmpty)

        // But the id must still have been adopted, so the next push updates
        // the existing row instead of uploading a brand-new one.
        await service.pushBatteryAsync(data: Data([0xBB]))
        #expect(fakes.updateSave.calls.count == 1)
        #expect(fakes.updateSave.calls.first?.id == 77)
        #expect(fakes.uploadSave.calls.isEmpty)
    }

    // MARK: - serverBatteryId learned deterministically among several rows

    /// There is no unique constraint on (rom_id, slot) server-side, so
    /// negotiate can return more than one non-state row for this ROM. The
    /// row whose name matches this device's own battery file name must win,
    /// no matter where it sits in the response, so the next push updates
    /// that row instead of a stray one belonging to a different save.
    ///
    /// Without the deterministic pick this fails: the old "last one wins"
    /// loop instead learns "other.sav" (id 200), the last matching entry in
    /// the response, and `pushBatteryAsync` would update the wrong row.
    @Test func serverBatteryIdPrefersTheRowMatchingThisDevicesFileNameOverTheLastOne() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        let response = makeNegotiateResponse(operations: [
            negotiateOperationJSON(action: .noOp, romId: 1, fileName: "battery.sav", saveId: 100),
            negotiateOperationJSON(action: .noOp, romId: 1, fileName: "other.sav", saveId: 200)
        ])
        let client = NegotiateStubAPIClient(response: response)

        let service = makeService(store: store, fakes: fakes, config: makeConfig(batteryFileName: "battery.sav"), apiClient: client)
        await service.pullBeforeLaunch()

        await service.pushBatteryAsync(data: Data([0xBB]))
        #expect(fakes.updateSave.calls.count == 1)
        #expect(fakes.updateSave.calls.first?.id == 100)
    }

    /// When none of the candidates' names match this device's own file name,
    /// the pick still has to be deterministic: the first candidate, not
    /// whichever the response happens to list last.
    @Test func serverBatteryIdPicksTheFirstCandidateWhenNoneMatchesTheFileName() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        let response = makeNegotiateResponse(operations: [
            negotiateOperationJSON(action: .noOp, romId: 1, fileName: "a.sav", saveId: 100),
            negotiateOperationJSON(action: .noOp, romId: 1, fileName: "b.sav", saveId: 200)
        ])
        let client = NegotiateStubAPIClient(response: response)

        let service = makeService(store: store, fakes: fakes, config: makeConfig(batteryFileName: "battery.sav"), apiClient: client)
        await service.pullBeforeLaunch()

        await service.pushBatteryAsync(data: Data([0xBB]))
        #expect(fakes.updateSave.calls.count == 1)
        #expect(fakes.updateSave.calls.first?.id == 100)
    }

    /// A row with a slot set to something other than the battery slot is not
    /// a battery row at all and must not be learned as one, even though its
    /// file name does not end in ".state". A `nil` slot (old server rows)
    /// still counts, since the server sends `null` for pre-existing battery
    /// saves.
    @Test func serverBatteryIdIgnoresARowWithADifferentSlot() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        let response = makeNegotiateResponse(operations: [
            negotiateOperationJSON(action: .noOp, romId: 1, fileName: "slotted.sav", saveId: 999, slot: "3")
        ])
        let client = NegotiateStubAPIClient(response: response)

        let service = makeService(store: store, fakes: fakes, config: makeConfig(), apiClient: client)
        await service.pullBeforeLaunch()

        await service.pushBatteryAsync(data: Data([0xBB]))
        #expect(fakes.uploadSave.calls.count == 1)
        #expect(fakes.updateSave.calls.isEmpty)
    }

    // MARK: - applyDownload only ever touches this device's own battery slot

    /// A `download` operation for a row parked under a different slot (e.g.
    /// another client's save under `slot=1`) is not this device's battery at
    /// all. It must not be written into the local battery file, and its id
    /// must not be adopted as `serverBatteryId` either, or every later push
    /// would overwrite that foreign row instead of this device's own.
    @Test func applyDownloadIgnoresARowWithADifferentSlot() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xAA]))
        let oldLocalTime = Date(timeIntervalSince1970: 1_600_000_000)
        try store.setBatteryModifiedAt(romId: 1, date: oldLocalTime)
        let fakes = Fakes()
        fakes.syncDevice.deviceIdToReturn = "device-1"
        let newerServerTime = oldLocalTime.addingTimeInterval(3600)
        let response = makeNegotiateResponse(operations: [
            negotiateOperationJSON(
                action: .download, romId: 1, fileName: "other-device.sav", saveId: 999, slot: "1",
                serverUpdatedAt: newerServerTime
            )
        ])
        let client = NegotiateStubAPIClient(response: response)
        fakes.downloadSave.dataForId[999] = Data([0xFF])

        let service = makeService(store: store, fakes: fakes, config: makeConfig(), apiClient: client)
        await service.pullBeforeLaunch()

        #expect(fakes.downloadSave.calls.isEmpty)
        #expect(try store.readBattery(romId: 1) == Data([0xAA]))

        // serverBatteryId must not have been adopted from the foreign-slot
        // row either, so the next push creates its own row rather than
        // updating the other device's.
        await service.pushBatteryAsync(data: Data([0xBB]))
        #expect(fakes.uploadSave.calls.count == 1)
        #expect(fakes.updateSave.calls.isEmpty)
    }
}
