import Testing
import Foundation
@testable import romm

// MARK: - Fakes

private final class FakeChainDownloadSaveUseCase: PDownloadSaveUseCase, @unchecked Sendable {
    var dataForId: [Int: Data] = [:]
    var error: Error?
    private(set) var calls: [(id: Int, deviceId: String?, sessionId: String?)] = []

    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data {
        calls.append((id, deviceId, sessionId))
        if let error { throw error }
        guard let data = dataForId[id] else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

/// Wraps a real `PSaveStore` but always fails `writeBattery`, to prove a
/// write failure propagates out of `apply` without reaching `confirm`.
private final class FailingWriteSaveStore: PSaveStore {
    private let wrapping: PSaveStore
    init(wrapping: PSaveStore) { self.wrapping = wrapping }

    func writeBattery(romId: Int, data: Data) throws {
        throw URLError(.cannotWriteToFile)
    }

    func readBattery(romId: Int) throws -> Data? { try wrapping.readBattery(romId: romId) }
    func batteryModifiedAt(romId: Int) -> Date? { wrapping.batteryModifiedAt(romId: romId) }
    func setBatteryModifiedAt(romId: Int, date: Date) throws { try wrapping.setBatteryModifiedAt(romId: romId, date: date) }
    func backupBattery(romId: Int, data: Data, origin: BatteryBackupOrigin) throws { try wrapping.backupBattery(romId: romId, data: data, origin: origin) }

    func listRomIds() throws -> [Int] { try wrapping.listRomIds() }
    func deleteSaves(romId: Int) throws { try wrapping.deleteSaves(romId: romId) }
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

private final class FakeChainConfirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase, @unchecked Sendable {
    var error: Error?
    private(set) var calls: [(id: Int, deviceId: String)] = []

    func execute(id: Int, deviceId: String) async throws -> SaveSchema {
        calls.append((id, deviceId))
        if let error { throw error }
        return SaveSchema(
            id: id, romId: 0, userId: 1, fileName: "battery.sav", fileNameNoTags: "battery.sav",
            fileNameNoExt: "battery", fileExtension: "sav", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: Date(),
            updatedAt: Date(), emulator: nil, screenshot: nil
        )
    }
}

// MARK: - Tests

@MainActor
struct BatteryDownloadChainTests {

    private func makeStore() -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatteryDownloadChainTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return LocalSaveStoreRepository(rootDirectory: tmp)
    }

    private struct Fakes {
        let download = FakeChainDownloadSaveUseCase()
        let confirm = FakeChainConfirmSaveDownloadUseCase()
    }

    private func makeChain(store: PSaveStore, fakes: Fakes) -> BatteryDownloadChain {
        BatteryDownloadChain(saveStore: store, downloadSaveUseCase: fakes.download, confirmSaveDownloadUseCase: fakes.confirm)
    }

    /// When `shouldWrite` allows it, the downloaded (and trimmed) bytes land on
    /// disk, the server timestamp is adopted, and the download is confirmed.
    @Test func appliesWritesTrimsAndConfirmsWhenWriteAllows() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.download.dataForId[9] = Data(repeating: 0x5A, count: 0x20000 + 16)
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        let chain = makeChain(store: store, fakes: fakes)

        let result = try await chain.apply(
            romId: 2, saveId: 9, deviceId: "device-1", serverUpdatedAt: serverTime, platformSlug: "gba"
        ) { _ in true }

        #expect(result.wrote)
        #expect(result.data.count == 0x20000)
        #expect(try store.readBattery(romId: 2)?.count == 0x20000)
        #expect(store.batteryModifiedAt(romId: 2) == serverTime)
        #expect(fakes.confirm.calls.map(\.id) == [9])
        #expect(fakes.confirm.calls.first?.deviceId == "device-1")
    }

    /// When `shouldWrite` declines (e.g. a blank candidate), nothing is written to
    /// disk, but the download is still confirmed so the server stops
    /// replanning it.
    @Test func skipsTheWriteButStillConfirmsWhenWriteDeclines() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 2, data: Data([0x01, 0x02, 0x03]))
        let fakes = Fakes()
        fakes.download.dataForId[9] = Data(repeating: 0xFF, count: 0x2000)
        let chain = makeChain(store: store, fakes: fakes)

        let result = try await chain.apply(
            romId: 2, saveId: 9, deviceId: "device-1", serverUpdatedAt: Date(), platformSlug: nil
        ) { _ in false }

        #expect(!result.wrote)
        #expect(try store.readBattery(romId: 2) == Data([0x01, 0x02, 0x03]))
        #expect(fakes.confirm.calls.map(\.id) == [9])
    }

    /// A download failure propagates to the caller and never reaches the
    /// confirmation step.
    @Test func downloadFailurePropagatesWithoutConfirming() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.download.error = URLError(.timedOut)
        let chain = makeChain(store: store, fakes: fakes)

        await #expect(throws: (any Error).self) {
            _ = try await chain.apply(
                romId: 2, saveId: 9, deviceId: "device-1", serverUpdatedAt: nil, platformSlug: nil
            ) { _ in true }
        }

        #expect(fakes.confirm.calls.isEmpty)
    }

    /// Confirming is best effort: a failure there is swallowed, not
    /// propagated, since the write already succeeded.
    @Test func confirmationFailureIsSwallowed() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.download.dataForId[9] = Data([0x01])
        fakes.confirm.error = URLError(.notConnectedToInternet)
        let chain = makeChain(store: store, fakes: fakes)

        let result = try await chain.apply(
            romId: 2, saveId: 9, deviceId: "device-1", serverUpdatedAt: nil, platformSlug: nil
        ) { _ in true }

        #expect(result.wrote)
        #expect(try store.readBattery(romId: 2) == Data([0x01]))
        #expect(fakes.confirm.calls.map(\.id) == [9])
    }

    /// A nil device id skips the confirmation entirely rather than calling
    /// the use case with a missing id.
    @Test func nilDeviceIdSkipsConfirmation() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.download.dataForId[9] = Data([0x01])
        let chain = makeChain(store: store, fakes: fakes)

        let result = try await chain.apply(
            romId: 2, saveId: 9, deviceId: nil, serverUpdatedAt: nil, platformSlug: nil
        ) { _ in true }

        #expect(result.wrote)
        #expect(fakes.confirm.calls.isEmpty)
    }

    /// A `writeBattery` failure (not download or confirm) propagates out of
    /// `apply`, and confirm is never reached since the throw happens before
    /// that call.
    @Test func writeFailurePropagatesWithoutConfirming() async throws {
        let store = makeStore()
        let failingStore = FailingWriteSaveStore(wrapping: store)
        let fakes = Fakes()
        fakes.download.dataForId[9] = Data([0x01])
        let chain = makeChain(store: failingStore, fakes: fakes)

        await #expect(throws: (any Error).self) {
            _ = try await chain.apply(
                romId: 2, saveId: 9, deviceId: "device-1", serverUpdatedAt: nil, platformSlug: nil
            ) { _ in true }
        }

        #expect(fakes.confirm.calls.isEmpty)
    }

    /// No server timestamp means nothing to adopt, but the write itself
    /// still happens.
    @Test func writesWithoutAdoptingATimestampWhenNoneIsGiven() async throws {
        let store = makeStore()
        let fakes = Fakes()
        fakes.download.dataForId[9] = Data([0x01])
        let chain = makeChain(store: store, fakes: fakes)

        _ = try await chain.apply(
            romId: 2, saveId: 9, deviceId: "device-1", serverUpdatedAt: nil, platformSlug: nil
        ) { _ in true }

        #expect(try store.readBattery(romId: 2) == Data([0x01]))
    }
}
