import Testing
import Foundation
@testable import romm

/// Answers negotiation with a canned plan and records what was reported.
private final class FakeNegotiateClient: StubRommAPIClient, @unchecked Sendable {
    var operations: [SyncOperationSchema] = []
    var errorToThrow: Error?
    private(set) var reportedSaves: [ClientSaveState] = []
    private(set) var reportedDeviceId: String?

    override func negotiateSync(_ body: SyncNegotiateRequest) async throws -> SyncNegotiateResponse {
        if let errorToThrow { throw errorToThrow }
        reportedSaves = body.saves
        reportedDeviceId = body.deviceId
        return Self.response(operations)
    }

    /// Builds a response through the decoder, since the schemas only have
    /// decoding initialisers.
    private static func response(_ operations: [SyncOperationSchema]) -> SyncNegotiateResponse {
        let payload: [String: Any] = [
            "session_id": 1,
            "operations": operations.map(Self.operationJSON),
            "total_upload": operations.filter { $0.action == .upload }.count,
            "total_download": operations.filter { $0.action == .download }.count,
            "total_conflict": operations.filter { $0.action == .conflict }.count,
            "total_no_op": operations.filter { $0.action == .noOp }.count
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(SyncNegotiateResponse.self, from: data)
    }

    private static func operationJSON(_ op: SyncOperationSchema) -> [String: Any] {
        var json: [String: Any] = ["action": op.action.rawValue]
        if let romId = op.romId { json["rom_id"] = romId }
        if let fileName = op.fileName { json["file_name"] = fileName }
        if let slot = op.slot { json["slot"] = slot }
        if let reason = op.reason { json["reason"] = reason }
        return json
    }
}

private final class FakeSyncDevice: PSyncDeviceRepository, @unchecked Sendable {
    var isSyncAPISupported: Bool = true
    var idToReturn: String? = "device-1"
    func deviceId() async -> String? { idToReturn }
}

private final class FakeTokenProvider: PTokenProvider, @unchecked Sendable {
    var serverURL: String? = "https://example.org"

    func getServerURL() -> String? { serverURL }
    func getAuthToken() -> String? { "token" }
    func getUsername() -> String? { "tester" }
    func getPassword() -> String? { nil }
    func isConfigured() -> Bool { serverURL != nil }
    func getAuthMethod() -> AuthMethod { .classic }
    func getClientToken() -> String? { nil }
    func getClientTokenInfo() -> ClientTokenInfo? { nil }
    func hasScope(_ scope: String) -> Bool { true }
    var availableScopes: [String]? { nil }
}

struct SyncPreviewUseCaseTests {

    private func makeStore() -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncPreviewUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return LocalSaveStoreRepository(rootDirectory: tmp)
    }

    private func makeUseCase(
        store: LocalSaveStoreRepository,
        client: FakeNegotiateClient = FakeNegotiateClient(),
        device: FakeSyncDevice = FakeSyncDevice(),
        token: FakeTokenProvider = FakeTokenProvider()
    ) -> SyncPreviewUseCase {
        SyncPreviewUseCase(saveStore: store, syncDevice: device, apiClient: client, tokenProvider: token)
    }

    private func operation(
        _ action: SyncAction,
        romId: Int? = 1,
        fileName: String? = "battery.sav",
        slot: String? = SaveSlot.battery,
        reason: String? = nil
    ) -> SyncOperationSchema {
        var json: [String: Any] = ["action": action.rawValue]
        if let romId { json["rom_id"] = romId }
        if let fileName { json["file_name"] = fileName }
        if let slot { json["slot"] = slot }
        if let reason { json["reason"] = reason }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(SyncOperationSchema.self, from: data)
    }

    // MARK: - What gets reported

    /// The slot is the whole point: the server never pairs a save that arrives
    /// without one, so a preview that omitted it would report every save as
    /// absent and plan an upload for all of them.
    @Test func reportsBatterySavesUnderTheBatterySlot() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 7, data: Data([0xCA, 0xFE]))
        let client = FakeNegotiateClient()

        _ = try await makeUseCase(store: store, client: client).execute()

        #expect(client.reportedSaves.count == 1)
        #expect(client.reportedSaves.first?.slot == SaveSlot.battery)
        #expect(client.reportedSaves.first?.romId == 7)
        #expect(client.reportedDeviceId == "device-1")
    }

    /// An empty battery file is not a save; reporting it would have the server
    /// plan an upload of nothing over a real save.
    @Test func skipsEmptyBatteryFiles() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 7, data: Data())
        let client = FakeNegotiateClient()

        _ = try await makeUseCase(store: store, client: client).execute()

        #expect(client.reportedSaves.isEmpty)
    }

    // MARK: - What comes back

    @Test func mapsEveryDirection() async throws {
        let client = FakeNegotiateClient()
        client.operations = [
            operation(.upload, romId: 1),
            operation(.download, romId: 2),
            operation(.conflict, romId: 3)
        ]

        let preview = try await makeUseCase(store: makeStore(), client: client).execute()

        #expect(preview.uploads.map(\.romId) == [1])
        #expect(preview.downloads.map(\.romId) == [2])
        #expect(preview.conflicts.map(\.romId) == [3])
        #expect(!preview.isUpToDate)
    }

    @Test func reportsAgreementWhenNothingWouldChange() async throws {
        let client = FakeNegotiateClient()
        client.operations = [operation(.noOp, romId: 1)]

        let preview = try await makeUseCase(store: makeStore(), client: client).execute()

        #expect(preview.isUpToDate)
    }

    /// This preview reports battery saves only, so an operation about a state
    /// came from somewhere else and would misstate what syncing here does.
    @Test func dropsSaveStateOperations() async throws {
        let client = FakeNegotiateClient()
        client.operations = [
            operation(.download, romId: 1, fileName: "slot0.state", slot: "0"),
            operation(.download, romId: 2, fileName: "battery.sav")
        ]

        let preview = try await makeUseCase(store: makeStore(), client: client).execute()

        #expect(preview.downloads.map(\.romId) == [2])
    }

    /// A newer server can plan something this build has no name for. Showing it
    /// as one of the four known directions would misdescribe a change the user
    /// is being asked to approve.
    @Test func dropsOperationsItCannotName() async throws {
        let client = FakeNegotiateClient()
        client.operations = [operation(.unknown, romId: 1), operation(.upload, romId: 2)]

        let preview = try await makeUseCase(store: makeStore(), client: client).execute()

        #expect(preview.operations.map(\.romId) == [2])
    }

    @Test func dropsOperationsWithoutARom() async throws {
        let client = FakeNegotiateClient()
        client.operations = [operation(.upload, romId: nil)]

        let preview = try await makeUseCase(store: makeStore(), client: client).execute()

        #expect(preview.operations.isEmpty)
    }

    /// The server's wording is kept rather than reworded, so a surprising plan
    /// can be traced back to what the server actually said.
    @Test func keepsTheServersReason() async throws {
        let client = FakeNegotiateClient()
        client.operations = [operation(.download, reason: "Server save is newer (no sync history)")]

        let preview = try await makeUseCase(store: makeStore(), client: client).execute()

        #expect(preview.downloads.first?.reason == "Server save is newer (no sync history)")
    }

    // MARK: - States the screen has to explain

    @Test func failsWithoutAServer() async throws {
        let token = FakeTokenProvider()
        token.serverURL = nil

        await #expect(throws: SyncPreviewError.notConnected) {
            try await makeUseCase(store: makeStore(), token: token).execute()
        }
    }

    @Test func failsOnAServerWithoutTheSyncAPI() async throws {
        let device = FakeSyncDevice()
        device.isSyncAPISupported = false

        await #expect(throws: SyncPreviewError.serverTooOld) {
            try await makeUseCase(store: makeStore(), device: device).execute()
        }
    }

    @Test func failsWhenTheDeviceCannotRegister() async throws {
        let device = FakeSyncDevice()
        device.idToReturn = nil

        await #expect(throws: SyncPreviewError.deviceRegistrationFailed) {
            try await makeUseCase(store: makeStore(), device: device).execute()
        }
    }

    @Test func surfacesANegotiationFailure() async throws {
        let client = FakeNegotiateClient()
        client.errorToThrow = URLError(.timedOut)

        await #expect(throws: SyncPreviewError.self) {
            try await makeUseCase(store: makeStore(), client: client).execute()
        }
    }
}
