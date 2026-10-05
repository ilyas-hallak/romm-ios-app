import Testing
import Foundation
@testable import romm

// MARK: - Fakes

private final class FakeConflictSyncDeviceRepository: PSyncDeviceRepository, @unchecked Sendable {
    var deviceIdToReturn: String? = "device-1"
    func syncAPIAvailability() async -> SyncAPIAvailability { .available }
    func deviceId() async -> String? { deviceIdToReturn }
    func forgetDevice() { deviceIdToReturn = nil }
    func completeSyncSession(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {}
}

private final class FakeConflictUploadSaveUseCase: PUploadSaveUseCase, @unchecked Sendable {
    private(set) var calls: [(romId: Int, slot: String?, deviceId: String?, autocleanup: Bool?, overwrite: Bool?, fileData: Data)] = []

    func execute(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, overwrite: Bool?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        calls.append((romId, slot, deviceId, autocleanup, overwrite, fileData))
        return Self.makeSchema(id: 1, romId: romId, fileName: fileName)
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

private final class FakeConflictDownloadSaveUseCase: PDownloadSaveUseCase, @unchecked Sendable {
    var dataForId: [Int: Data] = [:]
    var error: Error?
    private(set) var calls: [Int] = []

    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data {
        calls.append(id)
        if let error { throw error }
        guard let data = dataForId[id] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

private final class FakeConflictConfirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase, @unchecked Sendable {
    private(set) var calls: [(id: Int, deviceId: String)] = []

    func execute(id: Int, deviceId: String) async throws -> SaveSchema {
        calls.append((id, deviceId))
        return FakeConflictUploadSaveUseCase.makeSchema(id: id, romId: 0, fileName: "battery.sav")
    }
}

// MARK: - BatteryBackupNaming

@Suite
struct BatteryBackupNamingTests {
    @Test func fileNameIncludesOriginAndISOTimestamp() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = BatteryBackupNaming.fileName(at: date, origin: .local)
        #expect(name == "battery-2023-11-14T22:13:20Z-local.sav")
    }

    @Test func namesToPruneKeepsOnlyNewestWhenOverLimit() {
        let existing = (0..<12).map { "battery-2024-01-\(String(format: "%02d", $0 + 1))T00:00:00Z-local.sav" }
        let toPrune = BatteryBackupNaming.namesToPrune(existing: existing)
        #expect(toPrune.count == 2)
        #expect(toPrune == existing.sorted().prefix(2).map { $0 })
    }

    @Test func namesToPruneIsEmptyWhenAtOrUnderLimit() {
        let existing = (0..<10).map { "battery-2024-01-\(String(format: "%02d", $0 + 1))T00:00:00Z-local.sav" }
        #expect(BatteryBackupNaming.namesToPrune(existing: existing).isEmpty)
    }
}

// MARK: - LocalSaveStoreRepository.backupBattery

@Suite
struct LocalSaveStoreRepositoryBackupTests {
    private func makeStore() -> (LocalSaveStoreRepository, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (LocalSaveStoreRepository(rootDirectory: tmp), tmp)
    }

    @Test func pruneKeepsOnlyNewestTenBackups() throws {
        let (store, root) = makeStore()
        let dir = SaveStorePaths.backupsDir(root: root, romId: 1)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for day in 1...11 {
            let old = BatteryBackupNaming.fileName(at: Date(timeIntervalSince1970: Double(day) * 86_400), origin: .local)
            try Data([UInt8(day)]).write(to: dir.appendingPathComponent(old))
        }
        try store.backupBattery(romId: 1, data: Data([0x42]), origin: .local)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.count == 10)
        #expect(names.contains(BatteryBackupNaming.fileName(at: Date(timeIntervalSince1970: 86_400), origin: .local)) == false)
    }
}

// MARK: - BatteryConflictResolver

@MainActor
@Suite
struct BatteryConflictResolverTests {
    private func makeStore() -> (LocalSaveStoreRepository, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConflictResolverTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (LocalSaveStoreRepository(rootDirectory: tmp), tmp)
    }

    private struct Fakes {
        let upload = FakeConflictUploadSaveUseCase()
        let download = FakeConflictDownloadSaveUseCase()
        let confirm = FakeConflictConfirmSaveDownloadUseCase()
        let syncDevice = FakeConflictSyncDeviceRepository()
    }

    /// 0 whether the backups folder is empty or was never created.
    private func backupCount(in dir: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: dir.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).count
    }

    private func makeResolver(store: PSaveStore, fakes: Fakes) -> BatteryConflictResolver {
        BatteryConflictResolver(
            saveStore: store,
            uploadSaveUseCase: fakes.upload,
            downloadSaveUseCase: fakes.download,
            confirmSaveDownloadUseCase: fakes.confirm,
            syncDevice: fakes.syncDevice
        )
    }

    @Test func keepServerWritesTrimmedDataAndConfirmsDownload() async throws {
        let (store, root) = makeStore()
        try store.writeBattery(romId: 1, data: Data(repeating: 0xAB, count: 512))
        let fakes = Fakes()
        // 512 (a valid GBA size) + 16-byte footer, so trimming must strip it.
        let serverData = Data(repeating: 0xCD, count: 512) + Data(repeating: 0, count: 16)
        fakes.download.dataForId[42] = serverData
        let resolver = makeResolver(store: store, fakes: fakes)

        try await resolver.keepServer(romId: 1, saveId: 42, serverUpdatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let written = try store.readBattery(romId: 1)
        #expect(written == Data(repeating: 0xCD, count: 512))
        #expect(fakes.confirm.calls.count == 1)
        #expect(fakes.confirm.calls.first?.id == 42)
        #expect(fakes.confirm.calls.first?.deviceId == "device-1")

        // The discarded local version was backed up first.
        let backupsDir = SaveStorePaths.backupsDir(root: root, romId: 1)
        let backups = try FileManager.default.contentsOfDirectory(atPath: backupsDir.path)
        #expect(backups.count == 1)
        #expect(backups.first?.contains("-local.sav") == true)
    }

    @Test func keepServerSkipsBackupWhenLocalIsBlank() async throws {
        let (store, root) = makeStore()
        try store.writeBattery(romId: 1, data: Data(repeating: 0xFF, count: 512))
        let fakes = Fakes()
        fakes.download.dataForId[42] = Data(repeating: 0x11, count: 512)
        let resolver = makeResolver(store: store, fakes: fakes)

        try await resolver.keepServer(romId: 1, saveId: 42, serverUpdatedAt: nil)

        let backupsDir = SaveStorePaths.backupsDir(root: root, romId: 1)
        #expect(try backupCount(in: backupsDir) == 0)
    }

    @Test func keepServerAbortsWhenBackupFails() async throws {
        let (store, _) = makeStore()
        try store.writeBattery(romId: 1, data: Data(repeating: 0xAB, count: 512))
        let fakes = Fakes()
        fakes.download.dataForId[42] = Data(repeating: 0xCD, count: 512)
        // A store whose backup always fails stands in for a disk-full or
        // permission-denied condition: the resolution must abort before any
        // overwrite happens.
        let failingStore = FailingBackupSaveStore(wrapping: store)
        let resolver = makeResolver(store: failingStore, fakes: fakes)

        await #expect(throws: (any Error).self) {
            try await resolver.keepServer(romId: 1, saveId: 42, serverUpdatedAt: nil)
        }

        // Local battery must be untouched, and nothing downloaded or confirmed.
        #expect(try store.readBattery(romId: 1) == Data(repeating: 0xAB, count: 512))
        #expect(fakes.download.calls.isEmpty)
        #expect(fakes.confirm.calls.isEmpty)
    }

    @Test func keepThisDeviceBacksUpServerContentThenUploadsWithOverwrite() async throws {
        let (store, root) = makeStore()
        try store.writeBattery(romId: 1, data: Data(repeating: 0x42, count: 100))
        let fakes = Fakes()
        fakes.download.dataForId[42] = Data(repeating: 0x99, count: 200)
        let resolver = makeResolver(store: store, fakes: fakes)

        try await resolver.keepThisDevice(romId: 1, saveId: 42)

        let backupsDir = SaveStorePaths.backupsDir(root: root, romId: 1)
        let backups = try FileManager.default.contentsOfDirectory(atPath: backupsDir.path)
        #expect(backups.count == 1)
        #expect(backups.first?.contains("-server.sav") == true)

        #expect(fakes.upload.calls.count == 1)
        let call = fakes.upload.calls[0]
        #expect(call.romId == 1)
        #expect(call.slot == SaveSlot.battery)
        #expect(call.deviceId == "device-1")
        #expect(call.autocleanup == true)
        #expect(call.overwrite == true)
        #expect(call.fileData == Data(repeating: 0x42, count: 100))
    }

    @Test func keepThisDeviceSkipsServerBackupWhenServerDataIsBlank() async throws {
        let (store, root) = makeStore()
        try store.writeBattery(romId: 1, data: Data(repeating: 0x42, count: 100))
        let fakes = Fakes()
        fakes.download.dataForId[42] = Data(repeating: 0x00, count: 200)
        let resolver = makeResolver(store: store, fakes: fakes)

        try await resolver.keepThisDevice(romId: 1, saveId: 42)

        let backupsDir = SaveStorePaths.backupsDir(root: root, romId: 1)
        #expect(try backupCount(in: backupsDir) == 0)
        #expect(fakes.upload.calls.count == 1)
    }

    @Test func keepThisDeviceAbortsWhenNoLocalBattery() async throws {
        let (store, _) = makeStore()
        let fakes = Fakes()
        fakes.download.dataForId[42] = Data(repeating: 0x99, count: 200)
        let resolver = makeResolver(store: store, fakes: fakes)

        await #expect(throws: BatteryConflictResolutionError.self) {
            try await resolver.keepThisDevice(romId: 1, saveId: 42)
        }
        #expect(fakes.upload.calls.isEmpty)
    }

    @Test func keepThisDeviceAbortsWhenServerBackupFails() async throws {
        let (store, _) = makeStore()
        try store.writeBattery(romId: 1, data: Data(repeating: 0x42, count: 100))
        let fakes = Fakes()
        fakes.download.dataForId[42] = Data(repeating: 0x99, count: 200)
        let failingStore = FailingBackupSaveStore(wrapping: store)
        let resolver = makeResolver(store: failingStore, fakes: fakes)

        await #expect(throws: (any Error).self) {
            try await resolver.keepThisDevice(romId: 1, saveId: 42)
        }
        #expect(fakes.upload.calls.isEmpty)
    }
}

/// Wraps a real `PSaveStore` but always fails `backupBattery`, to prove a
/// failed backup aborts resolution before anything is overwritten.
private final class FailingBackupSaveStore: PSaveStore {
    private let wrapping: PSaveStore
    init(wrapping: PSaveStore) { self.wrapping = wrapping }

    func backupBattery(romId: Int, data: Data, origin: BatteryBackupOrigin) throws {
        throw URLError(.cannotWriteToFile)
    }

    func readBattery(romId: Int) throws -> Data? { try wrapping.readBattery(romId: romId) }
    func writeBattery(romId: Int, data: Data) throws { try wrapping.writeBattery(romId: romId, data: data) }
    func batteryModifiedAt(romId: Int) -> Date? { wrapping.batteryModifiedAt(romId: romId) }
    func setBatteryModifiedAt(romId: Int, date: Date) throws { try wrapping.setBatteryModifiedAt(romId: romId, date: date) }

    func listRomIds() throws -> [Int] { try wrapping.listRomIds() }
    func listStates(romId: Int) throws -> [SaveStateEntry] { try wrapping.listStates(romId: romId) }
    func readState(romId: Int, slot: Int) throws -> Data? { try wrapping.readState(romId: romId, slot: slot) }
    func writeState(romId: Int, slot: Int, data: Data) throws { try wrapping.writeState(romId: romId, slot: slot, data: data) }
    func deleteState(romId: Int, slot: Int) throws { try wrapping.deleteState(romId: romId, slot: slot) }
    func stateModifiedAt(romId: Int, slot: Int) -> Date? { wrapping.stateModifiedAt(romId: romId, slot: slot) }
    func setStateModifiedAt(romId: Int, slot: Int, date: Date) throws { try wrapping.setStateModifiedAt(romId: romId, slot: slot, date: date) }
    func readThumbnail(romId: Int, slot: Int) throws -> Data? { try wrapping.readThumbnail(romId: romId, slot: slot) }
    func writeThumbnail(romId: Int, slot: Int, data: Data) throws { try wrapping.writeThumbnail(romId: romId, slot: slot, data: data) }
    func deleteThumbnail(romId: Int, slot: Int) throws { try wrapping.deleteThumbnail(romId: romId, slot: slot) }
    func readStateBaseline(romId: Int, slot: Int) throws -> StateSyncBaseline? { try wrapping.readStateBaseline(romId: romId, slot: slot) }
    func writeStateBaseline(romId: Int, slot: Int, baseline: StateSyncBaseline) throws { try wrapping.writeStateBaseline(romId: romId, slot: slot, baseline: baseline) }
    func backupSlotForUndoSave(romId: Int, slot: Int) throws { try wrapping.backupSlotForUndoSave(romId: romId, slot: slot) }
    func restoreSlotFromUndoSave(romId: Int, slot: Int) throws -> Bool { try wrapping.restoreSlotFromUndoSave(romId: romId, slot: slot) }
    func hasUndoSave(romId: Int, slot: Int) -> Bool { wrapping.hasUndoSave(romId: romId, slot: slot) }
    func writeUndoLoadSnapshot(romId: Int, stateData: Data, thumbnailData: Data?) throws { try wrapping.writeUndoLoadSnapshot(romId: romId, stateData: stateData, thumbnailData: thumbnailData) }
    func readUndoLoadState(romId: Int) throws -> Data? { try wrapping.readUndoLoadState(romId: romId) }
    func readUndoLoadThumbnail(romId: Int) throws -> Data? { try wrapping.readUndoLoadThumbnail(romId: romId) }
    func hasUndoLoad(romId: Int) -> Bool { wrapping.hasUndoLoad(romId: romId) }
    func clearUndoLoad(romId: Int) throws { try wrapping.clearUndoLoad(romId: romId) }
}
