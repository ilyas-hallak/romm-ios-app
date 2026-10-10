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

    /// When `write` allows it, the downloaded (and trimmed) bytes land on
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

    /// When `write` declines (e.g. a blank candidate), nothing is written to
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
