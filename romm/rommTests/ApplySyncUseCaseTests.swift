import Testing
import Foundation
@testable import romm

private final class FakeLocalROMs: PLocalROMRepository, @unchecked Sendable {
    var roms: [DownloadedROM] = []

    var romsBaseURL: URL { FileManager.default.temporaryDirectory }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { roms }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { roms.first { $0.id == id } }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { roms.count }
}

private final class FakeHandoffStore: PExternalEmulatorHandoffStore, @unchecked Sendable {
    var identifiers: [Int: String] = [:]

    func hasHandedOff(romId: Int, to target: ExternalEmulatorID) -> Bool { false }
    func markHandedOff(romId: Int, to target: ExternalEmulatorID) {}
    func forget(romId: Int) {}
    func cachedGameIdentifier(romId: Int, kind: ExternalGameIdentifierKind) -> String? {
        identifiers[romId]
    }
    func cacheGameIdentifier(_ identifier: String, romId: Int, kind: ExternalGameIdentifierKind) {}
}

/// Records progress calls. A class rather than an array captured by a closure
/// directly: the callback is `@Sendable`, so what it captures has to answer
/// for its own safety, which `@unchecked Sendable` does here the same way the
/// project's other test doubles do.
private final class ProgressRecorder: @unchecked Sendable {
    private(set) var calls: [(completed: Int, total: Int)] = []
    func record(_ completed: Int, _ total: Int) { calls.append((completed, total)) }
}

@MainActor
struct ApplySyncUseCaseTests {

    // MARK: - Fixture

    private func makeStore() -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplySyncUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return LocalSaveStoreRepository(rootDirectory: tmp)
    }

    private func makeUseCase(
        store: PSaveStore,
        apiClient: FakeSyncApplyAPIClient = FakeSyncApplyAPIClient(),
        saveFiles: FakeExternalSaveFileRepository = FakeExternalSaveFileRepository(),
        localROMs: FakeLocalROMs = FakeLocalROMs(),
        handoffStore: FakeHandoffStore = FakeHandoffStore()
    ) -> ApplySyncUseCase {
        ApplySyncUseCase(
            apiClient: apiClient, saveStore: store, saveFiles: saveFiles,
            localROMs: localROMs, handoffStore: handoffStore
        )
    }

    private func preview(
        deviceId: String = "device-1",
        sessionId: Int? = 42,
        operations: [SyncPreviewOperation]
    ) -> SyncPreview {
        SyncPreview(
            deviceId: deviceId, sessionId: sessionId, reportedSaveCount: operations.count,
            reportedCountsBySource: [:], operations: operations
        )
    }

    private func operation(
        romId: Int = 1,
        direction: SyncPreviewOperation.Direction,
        saveId: Int? = nil,
        source: SyncSaveSource? = .internalStore,
        externalFile: ExternalSaveFile? = nil,
        serverUpdatedAt: Date? = nil,
        localUpdatedAt: Date? = nil
    ) -> SyncPreviewOperation {
        SyncPreviewOperation(
            romId: romId, direction: direction, saveId: saveId, serverFileName: nil,
            slot: source?.slot, emulator: nil, reason: nil, serverUpdatedAt: serverUpdatedAt,
            source: source, externalFile: externalFile, localUpdatedAt: localUpdatedAt
        )
    }

    /// Runs a plan with no resolutions and no interest in progress, for the
    /// tests that only care about the report.
    private func apply(
        _ useCase: ApplySyncUseCase, _ preview: SyncPreview,
        resolutions: [UUID: SyncConflictResolution] = [:]
    ) async -> SyncApplyReport {
        await useCase.execute(preview: preview, resolutions: resolutions) { _, _ in }
    }

    private func status(for op: SyncPreviewOperation, in report: SyncApplyReport) -> SyncApplyOutcome.Status? {
        report.outcomes.first { $0.operation.id == op.id }?.status
    }

    // MARK: - Upload / download

    @Test func uploadsAnInternalBatterySave() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 7, data: Data([0xCA, 0xFE]))
        let client = FakeSyncApplyAPIClient()
        let op = operation(romId: 7, direction: .upload)
        let p = preview(deviceId: "device-9", sessionId: 5, operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        #expect(client.uploadCalls.count == 1)
        let call = try #require(client.uploadCalls.first)
        #expect(call.romId == 7)
        #expect(call.slot == SaveSlot.battery)
        #expect(call.deviceId == "device-9")
        #expect(call.sessionId == 5)
        #expect(call.overwrite == false)
        #expect(call.fileData == Data([0xCA, 0xFE]))
        #expect(status(for: op, in: report) == .applied)
    }

    @Test func downloadsIntoTheInternalStore() async throws {
        let store = makeStore()
        let client = FakeSyncApplyAPIClient()
        client.downloadDataBySaveId[99] = Data([0x01, 0x02])
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        let op = operation(romId: 3, direction: .download, saveId: 99, serverUpdatedAt: serverTime)
        let p = preview(deviceId: "device-9", sessionId: 5, operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        let call = try #require(client.downloadCalls.first)
        #expect(call.id == 99)
        #expect(call.deviceId == "device-9")
        #expect(call.sessionId == 5)
        #expect(call.optimistic == false)
        #expect(try store.readBattery(romId: 3) == Data([0x01, 0x02]))
        let stored = try #require(store.batteryModifiedAt(romId: 3))
        #expect(abs(stored.timeIntervalSince(serverTime)) < 1)
        #expect(client.confirmCalls.first?.id == 99)
        #expect(status(for: op, in: report) == .applied)
    }

    // MARK: - Conflicts

    @Test func conflictWithoutADecisionIsLeftAlone() async throws {
        let store = makeStore()
        let client = FakeSyncApplyAPIClient()
        let op = operation(romId: 1, direction: .conflict, saveId: 5)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p, resolutions: [:])

        #expect(status(for: op, in: report) == .skipped(.conflictNotResolved))
        #expect(client.uploadCalls.isEmpty)
        #expect(client.updateCalls.isEmpty)
        #expect(client.downloadCalls.isEmpty)
    }

    @Test func conflictResolvedForTheLocalSideUpdatesTheExistingSave() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0x9]))
        let client = FakeSyncApplyAPIClient()
        let op = operation(romId: 1, direction: .conflict, saveId: 5)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p, resolutions: [op.id: .keepLocal])

        #expect(client.uploadCalls.isEmpty)
        let call = try #require(client.updateCalls.first)
        #expect(call.id == 5)
        #expect(call.fileData == Data([0x9]))
        #expect(status(for: op, in: report) == .applied)
    }

    @Test func conflictResolvedForTheServerSideDownloads() async throws {
        let store = makeStore()
        let client = FakeSyncApplyAPIClient()
        client.downloadDataBySaveId[5] = Data([0x3])
        let op = operation(romId: 1, direction: .conflict, saveId: 5)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p, resolutions: [op.id: .takeServer])

        #expect(client.downloadCalls.first?.id == 5)
        #expect(client.confirmCalls.first?.id == 5)
        #expect(status(for: op, in: report) == .applied)
    }

    @Test func conflictDeliberatelySkippedIsToldApartFromUndecided() async throws {
        let store = makeStore()
        let client = FakeSyncApplyAPIClient()
        let op = operation(romId: 1, direction: .conflict, saveId: 5)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p, resolutions: [op.id: .skip])

        #expect(status(for: op, in: report) == .skipped(.conflictSkipped))
        #expect(client.uploadCalls.isEmpty)
        #expect(client.downloadCalls.isEmpty)
    }

    // MARK: - Local file guard

    /// The reason a download checks the local file before fetching anything:
    /// an emulator writing a fresh save between preview and apply must not be
    /// silently overwritten by a plan made against the older file.
    @Test func doesNotOverwriteALocalSaveThatChangedSinceThePreview() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xAA]))
        let previewTime = Date(timeIntervalSince1970: 1_700_000_000)
        try store.setBatteryModifiedAt(romId: 1, date: previewTime.addingTimeInterval(3600))
        let client = FakeSyncApplyAPIClient()
        let op = operation(romId: 1, direction: .download, saveId: 5, localUpdatedAt: previewTime)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        #expect(status(for: op, in: report) == .skipped(.localSaveChanged))
        #expect(client.downloadCalls.isEmpty)
    }

    // MARK: - Operations the plan cannot address

    @Test func operationWithoutASourceIsAnUnknownSlot() async throws {
        let store = makeStore()
        let client = FakeSyncApplyAPIClient()
        let op = operation(romId: 1, direction: .upload, source: nil)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        #expect(status(for: op, in: report) == .skipped(.unknownSource))
    }

    @Test func downloadWithoutAServerSaveIdIsSkipped() async throws {
        let store = makeStore()
        let client = FakeSyncApplyAPIClient()
        let op = operation(romId: 1, direction: .download, saveId: nil)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        #expect(status(for: op, in: report) == .skipped(.noServerSave))
    }

    // MARK: - Session bookkeeping

    @Test func closesTheSessionWithTheActualCounts() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0x1]))
        try store.writeBattery(romId: 2, data: Data([0x2]))
        let client = FakeSyncApplyAPIClient()
        client.uploadErrorsByRomId[2] = FakeSyncApplyAPIError()
        let op1 = operation(romId: 1, direction: .upload)
        let op2 = operation(romId: 2, direction: .upload)
        let p = preview(sessionId: 42, operations: [op1, op2])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        #expect(client.completeCalls.first?.id == 42)
        #expect(client.completeCalls.first?.operationsCompleted == 1)
        #expect(client.completeCalls.first?.operationsFailed == 1)
        #expect(report.sessionClosed == true)
    }

    @Test func keepsTheOutcomesEvenWhenClosingTheSessionFails() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0x1]))
        let client = FakeSyncApplyAPIClient()
        client.completeSessionError = FakeSyncApplyAPIError()
        let op = operation(romId: 1, direction: .upload)
        let p = preview(operations: [op])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        #expect(report.sessionClosed == false)
        #expect(status(for: op, in: report) == .applied)
    }

    // MARK: - No-ops

    @Test func noOpOperationsDoNotAppearInTheReportOrCountTowardsProgress() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 2, data: Data([0x2]))
        let client = FakeSyncApplyAPIClient()
        let noOp = operation(romId: 1, direction: .noOp)
        let upload = operation(romId: 2, direction: .upload)
        let p = preview(operations: [noOp, upload])
        let recorder = ProgressRecorder()

        let report = await makeUseCase(store: store, apiClient: client).execute(
            preview: p, resolutions: [:]
        ) { completed, total in
            recorder.record(completed, total)
        }

        #expect(report.outcomes.count == 1)
        #expect(report.outcomes.first?.operation.romId == 2)
        // Only the real operation counts: a total of 2 would mean the no-op
        // was silently included in the plan.
        #expect(recorder.calls.map(\.completed) == [1])
        #expect(recorder.calls.map(\.total) == [1])
    }

    // MARK: - External apps

    @Test func externalDownloadWithoutAWritableDestinationIsSkipped() async throws {
        let store = makeStore()
        let client = FakeSyncApplyAPIClient()
        let localROMs = FakeLocalROMs()
        localROMs.roms = [DownloadedROM(
            id: 4, name: "Game", platformName: "GB", platformSlug: "gb",
            downloadedAt: Date(), totalSizeBytes: 10, localDirectory: "gb/game",
            files: [DownloadedROMFile(fileName: "game.gb", fileSizeBytes: 10)], urlCover: nil
        )]
        // `destinationsByBaseName` is left empty, so the fake reports no place
        // to write, the way a real folder without a matching file would.
        let op = operation(romId: 4, direction: .download, saveId: 11, source: .externalApp(.retroarch))
        let p = preview(operations: [op])

        let report = await apply(
            makeUseCase(store: store, apiClient: client, localROMs: localROMs), p
        )

        #expect(status(for: op, in: report) == .skipped(.noWritableDestination))
        #expect(client.downloadCalls.isEmpty)
    }

    // MARK: - Failures and progress

    @Test func aFailedUploadDoesNotStopTheRestOfThePlan() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0x1]))
        try store.writeBattery(romId: 2, data: Data([0x2]))
        let client = FakeSyncApplyAPIClient()
        client.uploadErrorsByRomId[1] = FakeSyncApplyAPIError()
        let op1 = operation(romId: 1, direction: .upload)
        let op2 = operation(romId: 2, direction: .upload)
        let p = preview(operations: [op1, op2])

        let report = await apply(makeUseCase(store: store, apiClient: client), p)

        guard case .failed = status(for: op1, in: report) else {
            Issue.record("expected op1 to fail, got \(String(describing: status(for: op1, in: report)))")
            return
        }
        #expect(status(for: op2, in: report) == .applied)
    }

    @Test func reportsProgressOnceEachWithAConstantTotal() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0x1]))
        try store.writeBattery(romId: 2, data: Data([0x2]))
        let client = FakeSyncApplyAPIClient()
        let op1 = operation(romId: 1, direction: .upload)
        let op2 = operation(romId: 2, direction: .upload)
        let p = preview(operations: [op1, op2])
        let recorder = ProgressRecorder()

        _ = await makeUseCase(store: store, apiClient: client).execute(
            preview: p, resolutions: [:]
        ) { completed, total in
            recorder.record(completed, total)
        }

        #expect(recorder.calls.map(\.completed) == [1, 2])
        #expect(recorder.calls.map(\.total) == [2, 2])
    }
}
