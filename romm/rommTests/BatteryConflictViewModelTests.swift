import Testing
import Foundation
@testable import romm

// MARK: - Fakes

private final class FakeListServerSavesUseCase: PListServerSavesUseCase, @unchecked Sendable {
    var saves: [SaveSchema] = []
    func execute(romId: Int) async throws -> [SaveSchema] { saves }
}

private final class FakeBatteryConflictResolver: PBatteryConflictResolver, @unchecked Sendable {
    var errorToThrow: Error?
    private(set) var keepThisDeviceCallCount = 0
    private(set) var keepServerCallCount = 0

    func keepServer(romId: Int, saveId: Int, serverUpdatedAt: Date?) async throws {
        keepServerCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }

    func keepThisDevice(romId: Int, saveId: Int) async throws {
        keepThisDeviceCallCount += 1
        if let errorToThrow { throw errorToThrow }
    }
}

/// Lets a test pause `keepThisDevice` mid-flight, so the re-entrancy guard can
/// be exercised against a call that is genuinely still in progress rather than
/// one that already finished.
private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private final class GatedBatteryConflictResolver: PBatteryConflictResolver, @unchecked Sendable {
    let gate = AsyncGate()
    private(set) var keepThisDeviceCallCount = 0

    func keepServer(romId: Int, saveId: Int, serverUpdatedAt: Date?) async throws {}

    func keepThisDevice(romId: Int, saveId: Int) async throws {
        keepThisDeviceCallCount += 1
        await gate.wait()
    }
}

// MARK: - Tests

@MainActor
struct BatteryConflictViewModelTests {

    private func makeStore(romId: Int? = nil, batteryData: Data? = nil) -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConflictViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = LocalSaveStoreRepository(rootDirectory: tmp)
        if let romId, let batteryData {
            try? store.writeBattery(romId: romId, data: batteryData)
        }
        return store
    }

    private func makeSaveSchema(
        id: Int,
        romId: Int,
        updatedAt: Date,
        fileSizeBytes: Int,
        originDeviceId: String? = nil,
        deviceSyncs: [DeviceSyncSchema]? = nil
    ) -> SaveSchema {
        SaveSchema(
            id: id, romId: romId, userId: 1, fileName: "battery.sav", fileNameNoTags: "battery",
            fileNameNoExt: "battery", fileExtension: "sav", filePath: "", fileSizeBytes: fileSizeBytes,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: updatedAt,
            updatedAt: updatedAt, emulator: nil, screenshot: nil,
            originDeviceId: originDeviceId, deviceSyncs: deviceSyncs
        )
    }

    private func makeViewModel(
        romId: Int = 1,
        saveId: Int = 42,
        store: PSaveStore,
        listSavesUseCase: FakeListServerSavesUseCase,
        resolver: PBatteryConflictResolver,
        onResolved: @escaping () async -> Void = {}
    ) -> BatteryConflictViewModel {
        BatteryConflictViewModel(
            romId: romId,
            saveId: saveId,
            saveStore: store,
            listSavesUseCase: listSavesUseCase,
            resolver: resolver,
            onResolved: onResolved
        )
    }

    // MARK: - load()

    @Test func loadPopulatesBothSides() async throws {
        let store = makeStore(romId: 1, batteryData: Data(repeating: 0xAB, count: 100))
        let listSavesUseCase = FakeListServerSavesUseCase()
        let serverDate = Date(timeIntervalSince1970: 1_700_000_000)
        listSavesUseCase.saves = [makeSaveSchema(id: 42, romId: 1, updatedAt: serverDate, fileSizeBytes: 200)]
        let viewModel = makeViewModel(store: store, listSavesUseCase: listSavesUseCase, resolver: FakeBatteryConflictResolver())

        await viewModel.load()

        guard case .ready(let local, let server) = viewModel.state else {
            Issue.record("expected .ready, got \(viewModel.state)")
            return
        }
        #expect(local.sizeBytes == 100)
        #expect(server.sizeBytes == 200)
        #expect(server.date == serverDate)
    }

    @Test func loadUsesTheMatchingDeviceSyncsDeviceName() async throws {
        let store = makeStore()
        let listSavesUseCase = FakeListServerSavesUseCase()
        listSavesUseCase.saves = [makeSaveSchema(
            id: 42, romId: 1, updatedAt: Date(), fileSizeBytes: 1,
            originDeviceId: "device-1",
            deviceSyncs: [DeviceSyncSchema(deviceId: "device-1", deviceName: "Ilyas' iPhone")]
        )]
        let viewModel = makeViewModel(store: store, listSavesUseCase: listSavesUseCase, resolver: FakeBatteryConflictResolver())

        await viewModel.load()

        guard case .ready(_, let server) = viewModel.state else {
            Issue.record("expected .ready, got \(viewModel.state)")
            return
        }
        #expect(server.deviceName == "Ilyas' iPhone")
    }

    @Test func loadFallsBackToTheOriginDeviceIdWhenNoDeviceNameIsKnown() async throws {
        let store = makeStore()
        let listSavesUseCase = FakeListServerSavesUseCase()
        listSavesUseCase.saves = [makeSaveSchema(
            id: 42, romId: 1, updatedAt: Date(), fileSizeBytes: 1,
            originDeviceId: "device-xyz", deviceSyncs: nil
        )]
        let viewModel = makeViewModel(store: store, listSavesUseCase: listSavesUseCase, resolver: FakeBatteryConflictResolver())

        await viewModel.load()

        guard case .ready(_, let server) = viewModel.state else {
            Issue.record("expected .ready, got \(viewModel.state)")
            return
        }
        #expect(server.deviceName == "device-xyz")
    }

    @Test func loadFailsWhenTheServerSaveIsGone() async throws {
        let store = makeStore()
        let listSavesUseCase = FakeListServerSavesUseCase()
        listSavesUseCase.saves = []
        let viewModel = makeViewModel(store: store, listSavesUseCase: listSavesUseCase, resolver: FakeBatteryConflictResolver())

        await viewModel.load()

        guard case .failed = viewModel.state else {
            Issue.record("expected .failed, got \(viewModel.state)")
            return
        }
    }

    // MARK: - keepThisDevice() / keepServer()

    @Test func keepThisDeviceCallsOnResolvedOnSuccess() async throws {
        let store = makeStore()
        var onResolvedCallCount = 0
        let viewModel = makeViewModel(
            store: store, listSavesUseCase: FakeListServerSavesUseCase(), resolver: FakeBatteryConflictResolver(),
            onResolved: { onResolvedCallCount += 1 }
        )

        await viewModel.keepThisDevice()

        #expect(onResolvedCallCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func keepThisDeviceSetsErrorMessageAndSkipsOnResolvedOnFailure() async throws {
        let store = makeStore()
        let resolver = FakeBatteryConflictResolver()
        resolver.errorToThrow = BatteryConflictResolutionError.noLocalBattery
        var onResolvedCallCount = 0
        let viewModel = makeViewModel(
            store: store, listSavesUseCase: FakeListServerSavesUseCase(), resolver: resolver,
            onResolved: { onResolvedCallCount += 1 }
        )

        await viewModel.keepThisDevice()

        #expect(onResolvedCallCount == 0)
        #expect(viewModel.errorMessage == BatteryConflictResolutionError.noLocalBattery.errorDescription)
    }

    @Test func keepServerCallsOnResolvedOnSuccess() async throws {
        let store = makeStore()
        let listSavesUseCase = FakeListServerSavesUseCase()
        listSavesUseCase.saves = [makeSaveSchema(id: 42, romId: 1, updatedAt: Date(), fileSizeBytes: 1)]
        var onResolvedCallCount = 0
        let viewModel = makeViewModel(
            store: store, listSavesUseCase: listSavesUseCase, resolver: FakeBatteryConflictResolver(),
            onResolved: { onResolvedCallCount += 1 }
        )
        await viewModel.load()

        await viewModel.keepServer()

        #expect(onResolvedCallCount == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func keepServerDoesNothingBeforeTheSideIsLoaded() async throws {
        let store = makeStore()
        let resolver = FakeBatteryConflictResolver()
        var onResolvedCallCount = 0
        let viewModel = makeViewModel(
            store: store, listSavesUseCase: FakeListServerSavesUseCase(), resolver: resolver,
            onResolved: { onResolvedCallCount += 1 }
        )

        // state is still .loading: keepServer can't read the server side yet.
        await viewModel.keepServer()

        #expect(resolver.keepServerCallCount == 0)
        #expect(onResolvedCallCount == 0)
    }

    // MARK: - Re-entrancy guard

    @Test func aSecondResolveWhileOneIsInFlightIsIgnored() async throws {
        let store = makeStore()
        let resolver = GatedBatteryConflictResolver()
        let viewModel = makeViewModel(store: store, listSavesUseCase: FakeListServerSavesUseCase(), resolver: resolver)

        let firstCall = Task { await viewModel.keepThisDevice() }
        while resolver.keepThisDeviceCallCount == 0 { await Task.yield() }
        #expect(viewModel.isResolving == true)

        // The resolver is still suspended inside `wait()`: a second call must
        // be rejected by the guard rather than starting another resolution.
        await viewModel.keepThisDevice()
        #expect(resolver.keepThisDeviceCallCount == 1)

        await resolver.gate.open()
        await firstCall.value
        #expect(viewModel.isResolving == false)
    }
}
