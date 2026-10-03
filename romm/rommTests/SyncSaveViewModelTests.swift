import Testing
import Foundation
@testable import romm

// MARK: - Fakes

private final class FakeSyncDeviceRepo: PSyncDeviceRepository, @unchecked Sendable {
    var deviceIdToReturn: String?
    func syncAPIAvailability() async -> SyncAPIAvailability { .available }
    func deviceId() async -> String? { deviceIdToReturn }
    func forgetDevice() { deviceIdToReturn = nil }
    func completeSyncSession(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {}
}

private final class FakeUploadSaveUseCase: PUploadSaveUseCase, @unchecked Sendable {
    var error: Error?
    private(set) var calls: [(romId: Int, slot: String?, deviceId: String?, autocleanup: Bool?, overwrite: Bool?, fileName: String)] = []

    func execute(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, overwrite: Bool?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        if let error { throw error }
        calls.append((romId, slot, deviceId, autocleanup, overwrite, fileName))
        return Self.makeSchema(id: 999, romId: romId, fileName: fileName)
    }

    static func makeSchema(id: Int, romId: Int, fileName: String) -> SaveSchema {
        SaveSchema(
            id: id, romId: romId, userId: 1, fileName: fileName, fileNameNoTags: fileName,
            fileNameNoExt: fileName, fileExtension: "sav", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: Date(),
            updatedAt: Date(), emulator: nil, screenshot: nil
        )
    }
}

private final class FakeUpdateSaveUseCase: PUpdateSaveUseCase, @unchecked Sendable {
    private(set) var calls: [(id: Int, deviceId: String?, fileName: String)] = []
    func execute(id: Int, emulator: String?, deviceId: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        calls.append((id, deviceId, fileName))
        return FakeUploadSaveUseCase.makeSchema(id: id, romId: 0, fileName: fileName)
    }
}

private final class UnusedListServerSavesUseCase: PListServerSavesUseCase {
    func execute(romId: Int) async throws -> [SaveSchema] { [] }
}

private final class UnusedListServerStatesUseCase: PListServerStatesUseCase {
    func execute(romId: Int) async throws -> [StateSchema] { [] }
}

private final class UnusedDownloadSaveUseCase: PDownloadSaveUseCase {
    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data { Data() }
}

private final class UnusedDownloadStateUseCase: PDownloadStateUseCase {
    func execute(id: Int) async throws -> Data { Data() }
}

private final class UnusedUploadStateUseCase: PUploadStateUseCase {
    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}

private final class UnusedUpdateStateUseCase: PUpdateStateUseCase {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
    }
}

private final class UnusedConfirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase {
    func execute(id: Int, deviceId: String) async throws -> SaveSchema {
        fatalError("not used in these tests")
    }
}

private final class FakeRecordSyncUseCase: PRecordSyncUseCase {
    func execute(romId: Int, trigger: SyncTrigger) {}
}

private final class FakeGetLastSyncUseCase: PGetLastSyncUseCase {
    func execute(romId: Int) -> SyncMetadata? { nil }
}

// MARK: - Tests

/// The manual battery upload must identify itself with the `battery` slot and
/// this device's id, so the server can pair it by `(rom_id, slot)` and apply
/// per-device bookkeeping, and must win over whatever is already in that slot
/// since the user explicitly asked for this upload (see
/// `SaveSyncRunner.runBatteryUpload` for the same reasoning on the automatic path).
@MainActor
struct SyncSaveViewModelTests {

    private func makeStore(romId: Int, data: Data) -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncSaveViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = LocalSaveStoreRepository(rootDirectory: tmp)
        try? store.writeBattery(romId: romId, data: data)
        return store
    }

    private func makeRom(id: Int = 1) -> DownloadedROM {
        DownloadedROM(
            id: id, name: "Test Game", platformName: "SNES", platformSlug: "snes",
            downloadedAt: Date(), totalSizeBytes: 0, localDirectory: "snes/test",
            files: [DownloadedROMFile(fileName: "test.sfc", fileSizeBytes: 0)], urlCover: nil
        )
    }

    private func makeViewModel(
        rom: DownloadedROM,
        uploadSave: FakeUploadSaveUseCase,
        updateSave: FakeUpdateSaveUseCase,
        syncDevice: FakeSyncDeviceRepo,
        store: PSaveStore
    ) -> SyncSaveViewModel {
        SyncSaveViewModel(
            rom: rom,
            listSavesUseCase: UnusedListServerSavesUseCase(),
            listStatesUseCase: UnusedListServerStatesUseCase(),
            downloadSaveUseCase: UnusedDownloadSaveUseCase(),
            downloadStateUseCase: UnusedDownloadStateUseCase(),
            uploadSaveUseCase: uploadSave,
            updateSaveUseCase: updateSave,
            uploadStateUseCase: UnusedUploadStateUseCase(),
            updateStateUseCase: UnusedUpdateStateUseCase(),
            confirmSaveDownloadUseCase: UnusedConfirmSaveDownloadUseCase(),
            saveStore: store,
            syncDevice: syncDevice,
            recordSyncUseCase: FakeRecordSyncUseCase(),
            getLastSyncUseCase: FakeGetLastSyncUseCase()
        )
    }

    @Test func freshBatteryUploadSendsBatterySlotDeviceIdAndOverwrite() async throws {
        let rom = makeRom()
        let store = makeStore(romId: rom.id, data: Data([0x01, 0x02]))
        let uploadSave = FakeUploadSaveUseCase()
        let updateSave = FakeUpdateSaveUseCase()
        let syncDevice = FakeSyncDeviceRepo()
        syncDevice.deviceIdToReturn = "device-1"
        let viewModel = makeViewModel(rom: rom, uploadSave: uploadSave, updateSave: updateSave, syncDevice: syncDevice, store: store)

        // No existing server save for this ROM, so this goes straight to upload
        // without routing through the overwrite-confirmation prompt.
        viewModel.uploadLocalBattery()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(uploadSave.calls.count == 1)
        let call = try #require(uploadSave.calls.first)
        #expect(call.slot == SaveSlot.battery)
        #expect(call.deviceId == "device-1")
        #expect(call.autocleanup == true)
        #expect(call.overwrite == true)
        #expect(updateSave.calls.isEmpty)
    }

    @Test func batteryUploadOverExistingRowUpdatesWithDeviceId() async throws {
        let rom = makeRom()
        let store = makeStore(romId: rom.id, data: Data([0x03]))
        let uploadSave = FakeUploadSaveUseCase()
        let updateSave = FakeUpdateSaveUseCase()
        let syncDevice = FakeSyncDeviceRepo()
        syncDevice.deviceIdToReturn = "device-2"
        let viewModel = makeViewModel(rom: rom, uploadSave: uploadSave, updateSave: updateSave, syncDevice: syncDevice, store: store)
        viewModel.serverSaves = [FakeUploadSaveUseCase.makeSchema(id: 42, romId: rom.id, fileName: "battery.sav")]

        // An existing server save routes through the overwrite prompt first.
        viewModel.uploadLocalBattery()
        viewModel.confirmUpload(update: true)
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(uploadSave.calls.isEmpty)
        #expect(updateSave.calls.count == 1)
        #expect(updateSave.calls.first?.id == 42)
        #expect(updateSave.calls.first?.deviceId == "device-2")
    }
}
