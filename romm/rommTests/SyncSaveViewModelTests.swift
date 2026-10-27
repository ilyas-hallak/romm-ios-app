import Testing
import Foundation
@testable import romm

// MARK: - Fakes

/// Scriptable stand-in for negotiate, scoped to one ROM: records the romIds
/// filter it was called with so a test can confirm scoping, and whether it
/// ran more than once per `syncThisGame()` call.
private final class FakeSyncPreviewUseCase: PSyncPreviewUseCase, @unchecked Sendable {
    var result: Result<SyncPreview, Error>
    private(set) var callCount = 0
    private(set) var lastRomIds: [Int]?

    init(result: Result<SyncPreview, Error>) { self.result = result }

    func execute(romIds: [Int]?) async throws -> SyncPreview {
        callCount += 1
        lastRomIds = romIds
        return try result.get()
    }
}

private final class FakeSaveSyncRunner: PSaveSyncRunner, @unchecked Sendable {
    var reportToReturn = SaveSyncReport()
    private(set) var callCount = 0
    private(set) var lastStateRomIds: [Int]?

    func run(preview: SyncPreview, externalScans: [ExternalEmulatorID: ExternalSaveScan], stateRomIds: [Int]?) async -> SaveSyncReport {
        callCount += 1
        lastStateRomIds = stateRomIds
        return reportToReturn
    }
}

private final class FakeListServerSavesUseCase: PListServerSavesUseCase, @unchecked Sendable {
    var saves: [SaveSchema] = []
    func execute(romId: Int) async throws -> [SaveSchema] { saves }
}

private final class FakeDownloadSaveUseCase: PDownloadSaveUseCase, @unchecked Sendable {
    var data = Data()
    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data { data }
}

private final class FakeSyncDeviceRepo: PSyncDeviceRepository, @unchecked Sendable {
    var deviceIdToReturn: String?
    func syncAPIAvailability() async -> SyncAPIAvailability { .available }
    func deviceId() async -> String? { deviceIdToReturn }
    func forgetDevice() { deviceIdToReturn = nil }
    func completeSyncSession(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {}
}

private final class FakeRecordSyncUseCase: PRecordSyncUseCase, @unchecked Sendable {
    private(set) var calls: [(romId: Int, trigger: SyncTrigger)] = []
    func execute(romId: Int, trigger: SyncTrigger) { calls.append((romId, trigger)) }
}

private final class FakeGetLastSyncUseCase: PGetLastSyncUseCase, @unchecked Sendable {
    var metaToReturn: SyncMetadata?
    func execute(romId: Int) -> SyncMetadata? { metaToReturn }
}

/// Stub use cases so a real `StateSyncCoordinator` can be built without ever
/// reaching the network; `statusSummary` itself is already covered by
/// `StateSyncCoordinatorTests`, so these tests only need it to report `.inSync`.
private final class StubListStatesUseCase: PListServerStatesUseCase, @unchecked Sendable {
    func execute(romId: Int) async throws -> [StateSchema] { [] }
}

private final class StubUploadStateUseCase: PUploadStateUseCase, @unchecked Sendable {
    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}

private final class StubUpdateStateUseCase: PUpdateStateUseCase, @unchecked Sendable {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}

private final class StubDownloadStateUseCase: PDownloadStateUseCase, @unchecked Sendable {
    func execute(id: Int) async throws -> Data { fatalError("not used in these tests") }
}

// MARK: - Tests

@MainActor
struct SyncSaveViewModelTests {

    private func makeStore(romId: Int? = nil, batteryData: Data? = nil) -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncSaveViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = LocalSaveStoreRepository(rootDirectory: tmp)
        if let romId, let batteryData {
            try? store.writeBattery(romId: romId, data: batteryData)
        }
        return store
    }

    private func makeRom(id: Int = 1) -> DownloadedROM {
        DownloadedROM(
            id: id, name: "Test Game", platformName: "SNES", platformSlug: "snes",
            downloadedAt: Date(), totalSizeBytes: 0, localDirectory: "snes/test",
            files: [DownloadedROMFile(fileName: "test.sfc", fileSizeBytes: 0)], urlCover: nil
        )
    }

    private func makePreview(romId: Int, operations: [SyncPreviewOperation] = []) -> SyncPreview {
        SyncPreview(deviceId: "device-1", reportedSaveCount: 1, operations: operations)
    }

    private func makeOperation(romId: Int, direction: SyncPreviewOperation.Direction, saveId: Int? = nil) -> SyncPreviewOperation {
        var operation = SyncPreviewOperation(
            romId: romId, direction: direction, serverFileName: "battery.sav", slot: SaveSlot.battery,
            emulator: nil, reason: nil, serverUpdatedAt: nil
        )
        operation.saveId = saveId
        return operation
    }

    private func makeCoordinator(store: PSaveStore) -> StateSyncCoordinator {
        StateSyncCoordinator(
            saveStore: store,
            listStatesUseCase: StubListStatesUseCase(),
            uploadStateUseCase: StubUploadStateUseCase(),
            updateStateUseCase: StubUpdateStateUseCase(),
            downloadStateUseCase: StubDownloadStateUseCase()
        )
    }

    private func makeViewModel(
        rom: DownloadedROM,
        store: PSaveStore,
        previewUseCase: FakeSyncPreviewUseCase,
        syncRunner: FakeSaveSyncRunner,
        listSavesUseCase: FakeListServerSavesUseCase = FakeListServerSavesUseCase(),
        downloadSaveUseCase: FakeDownloadSaveUseCase = FakeDownloadSaveUseCase(),
        syncDevice: FakeSyncDeviceRepo = FakeSyncDeviceRepo(),
        recordSyncUseCase: FakeRecordSyncUseCase = FakeRecordSyncUseCase(),
        getLastSyncUseCase: FakeGetLastSyncUseCase = FakeGetLastSyncUseCase()
    ) -> SyncSaveViewModel {
        SyncSaveViewModel(
            rom: rom,
            previewUseCase: previewUseCase,
            syncRunner: syncRunner,
            stateSyncCoordinator: makeCoordinator(store: store),
            listSavesUseCase: listSavesUseCase,
            downloadSaveUseCase: downloadSaveUseCase,
            saveStore: store,
            syncDevice: syncDevice,
            recordSyncUseCase: recordSyncUseCase,
            getLastSyncUseCase: getLastSyncUseCase
        )
    }

    // MARK: - load()

    @Test func loadNegotiatesScopedToThisRomOnly() async throws {
        let rom = makeRom(id: 7)
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(makePreview(romId: 7)))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        #expect(previewUseCase.lastRomIds == [7])
        #expect(previewUseCase.callCount == 1)
        #expect(viewModel.preview != nil)
    }

    @Test func loadSurfacesANegotiationFailure() async throws {
        let rom = makeRom()
        let previewUseCase = FakeSyncPreviewUseCase(result: .failure(SyncPreviewError.notConnected))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        guard case .failed(let error) = viewModel.state else {
            Issue.record("expected .failed, got \(viewModel.state)")
            return
        }
        #expect(error == .notConnected)
    }

    @Test func batteryStatusReflectsTheOnlyOperationInThePlan() async throws {
        let rom = makeRom(id: 3)
        let preview = makePreview(romId: 3, operations: [makeOperation(romId: 3, direction: .upload)])
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(preview))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        #expect(viewModel.batteryStatus == .willUpload)
    }

    @Test func batteryStatusIsNoSaveYetWhenThePlanHasNoOperationForThisRom() async throws {
        let rom = makeRom(id: 4)
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(makePreview(romId: 4)))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        #expect(viewModel.batteryStatus == .noSaveYet)
    }

    @Test func conflictSaveIdIsNilWhenThereIsNoConflict() async throws {
        let rom = makeRom(id: 5)
        let preview = makePreview(romId: 5, operations: [makeOperation(romId: 5, direction: .upload, saveId: 77)])
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(preview))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        #expect(viewModel.conflictSaveId == nil)
    }

    @Test func conflictSaveIdReturnsTheConflictingOperationsSaveId() async throws {
        let rom = makeRom(id: 6)
        let preview = makePreview(romId: 6, operations: [makeOperation(romId: 6, direction: .conflict, saveId: 88)])
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(preview))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        #expect(viewModel.conflictSaveId == 88)
    }

    @Test func batteryStatusIsConflictEvenWhenItIsNotTheFirstOperation() async throws {
        let rom = makeRom(id: 5)
        let preview = makePreview(romId: 5, operations: [
            makeOperation(romId: 5, direction: .noOp),
            makeOperation(romId: 5, direction: .conflict)
        ])
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(preview))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        #expect(viewModel.batteryStatus == .conflict)
    }

    @Test func batteryStatusPrefersDownloadOverUploadWhenBothArePlanned() async throws {
        let rom = makeRom(id: 6)
        let preview = makePreview(romId: 6, operations: [
            makeOperation(romId: 6, direction: .upload),
            makeOperation(romId: 6, direction: .download)
        ])
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(preview))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.load()

        #expect(viewModel.batteryStatus == .willDownload)
    }

    // MARK: - syncThisGame()

    @Test func syncThisGameRenegotiatesBeforeRunningAndScopesTheStatesPass() async throws {
        let rom = makeRom(id: 9)
        let preview = makePreview(romId: 9, operations: [makeOperation(romId: 9, direction: .upload)])
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(preview))
        let syncRunner = FakeSaveSyncRunner()
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: syncRunner
        )
        await viewModel.load()

        await viewModel.syncThisGame()

        // Once for load(), once for the re-negotiate inside syncThisGame(),
        // once more for the load() that follows the run.
        #expect(previewUseCase.callCount == 3)
        #expect(syncRunner.callCount == 1)
        #expect(syncRunner.lastStateRomIds == [9])
    }

    @Test func syncThisGameRecordsAManualSync() async throws {
        let rom = makeRom(id: 11)
        let preview = makePreview(romId: 11, operations: [makeOperation(romId: 11, direction: .upload)])
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(preview))
        let recordSyncUseCase = FakeRecordSyncUseCase()
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner(),
            recordSyncUseCase: recordSyncUseCase
        )
        await viewModel.load()

        await viewModel.syncThisGame()

        #expect(recordSyncUseCase.calls.count == 1)
        #expect(recordSyncUseCase.calls.first?.romId == 11)
        #expect(recordSyncUseCase.calls.first?.trigger == .manual)
    }

    @Test func syncThisGameDoesNothingWhenAlreadyUpToDate() async throws {
        let rom = makeRom(id: 12)
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(makePreview(romId: 12)))
        let syncRunner = FakeSaveSyncRunner()
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: syncRunner
        )
        await viewModel.load()

        #expect(viewModel.canSync == false)
        await viewModel.syncThisGame()

        #expect(syncRunner.callCount == 0)
    }

    // MARK: - Export

    @Test func exportLocalBatterySharesTheLocalFile() async throws {
        let rom = makeRom(id: 20)
        let store = makeStore(romId: 20, batteryData: Data([0xAA, 0xBB]))
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(makePreview(romId: 20)))
        let viewModel = makeViewModel(
            rom: rom, store: store, previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        viewModel.exportLocalBattery()

        let item = try #require(viewModel.exportItem)
        #expect(try Data(contentsOf: item.url) == Data([0xAA, 0xBB]))
        #expect(viewModel.errorMessage == nil)
    }

    @Test func exportLocalBatteryFailsWithNoLocalSave() async throws {
        let rom = makeRom(id: 21)
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(makePreview(romId: 21)))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        viewModel.exportLocalBattery()

        #expect(viewModel.exportItem == nil)
        #expect(viewModel.errorMessage != nil)
    }

    @Test func exportServerBatteryDownloadsAndSharesTheServerFile() async throws {
        let rom = makeRom(id: 22)
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(makePreview(romId: 22)))
        let listSavesUseCase = FakeListServerSavesUseCase()
        listSavesUseCase.saves = [makeSaveSchema(id: 55, romId: 22)]
        let downloadSaveUseCase = FakeDownloadSaveUseCase()
        downloadSaveUseCase.data = Data([0x01, 0x02, 0x03])
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner(),
            listSavesUseCase: listSavesUseCase, downloadSaveUseCase: downloadSaveUseCase
        )

        await viewModel.exportServerBattery()

        let item = try #require(viewModel.exportItem)
        #expect(try Data(contentsOf: item.url) == Data([0x01, 0x02, 0x03]))
    }

    @Test func exportServerBatteryFailsWithNoServerSave() async throws {
        let rom = makeRom(id: 23)
        let previewUseCase = FakeSyncPreviewUseCase(result: .success(makePreview(romId: 23)))
        let viewModel = makeViewModel(
            rom: rom, store: makeStore(), previewUseCase: previewUseCase, syncRunner: FakeSaveSyncRunner()
        )

        await viewModel.exportServerBattery()

        #expect(viewModel.exportItem == nil)
        #expect(viewModel.errorMessage != nil)
    }

    private func makeSaveSchema(id: Int, romId: Int) -> SaveSchema {
        SaveSchema(
            id: id, romId: romId, userId: 1, fileName: "battery.sav", fileNameNoTags: "battery",
            fileNameNoExt: "battery", fileExtension: "sav", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: Date(),
            updatedAt: Date(), emulator: nil, screenshot: nil
        )
    }
}
