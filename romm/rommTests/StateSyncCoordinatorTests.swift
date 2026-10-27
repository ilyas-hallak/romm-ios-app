import Testing
import Foundation
@testable import romm

private final class ListStatesStub: PListServerStatesUseCase, @unchecked Sendable {
    var states: [StateSchema] = []
    var error: Error?

    func execute(romId: Int) async throws -> [StateSchema] {
        if let error { throw error }
        return states
    }
}

private final class UploadStateSpy: PUploadStateUseCase, @unchecked Sendable {
    private(set) var emulators: [String?] = []

    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        emulators.append(emulator)
        return makeState(id: 40, fileName: fileName, updatedAt: Date())
    }
}

private final class UpdateStateSpy: PUpdateStateUseCase, @unchecked Sendable {
    private(set) var emulators: [String?] = []

    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        emulators.append(emulator)
        return makeState(id: id, fileName: fileName, updatedAt: Date())
    }
}

private final class DownloadStateStub: PDownloadStateUseCase, @unchecked Sendable {
    var data: Data?
    private(set) var callCount = 0

    func execute(id: Int) async throws -> Data {
        callCount += 1
        guard let data else { throw URLError(.fileDoesNotExist) }
        return data
    }
}

private func makeState(id: Int, fileName: String, updatedAt: Date) -> StateSchema {
    StateSchema(
        id: id, romId: 1, userId: 1, fileName: fileName, fileNameNoTags: fileName,
        fileNameNoExt: fileName, fileExtension: "state", filePath: "", fileSizeBytes: 0,
        fullPath: "", downloadPath: "", missingFromFs: false, createdAt: updatedAt,
        updatedAt: updatedAt, emulator: nil, screenshot: nil
    )
}

struct StateSyncCoordinatorTests {
    private let listStates = ListStatesStub()
    private let uploadState = UploadStateSpy()
    private let updateState = UpdateStateSpy()
    private let downloadState = DownloadStateStub()
    private let store: LocalSaveStoreRepository = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StateSyncCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return LocalSaveStoreRepository(rootDirectory: dir)
    }()

    private func makeCoordinator() -> StateSyncCoordinator {
        StateSyncCoordinator(
            saveStore: store,
            listStatesUseCase: listStates,
            uploadStateUseCase: uploadState,
            updateStateUseCase: updateState,
            downloadStateUseCase: downloadState
        )
    }

    @Test func pushAfterASaveTagsTheStateWithTheEmulator() async throws {
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))

        let outcome = await makeCoordinator().syncSlot(romId: 1, slot: 0, emulator: "delta-ios")

        guard case .uploaded = outcome else { Issue.record("expected upload, got \(outcome)"); return }
        #expect(uploadState.emulators == ["delta-ios"])
    }

    @Test func pushUpdatesTheKnownRowInPlace() async throws {
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        let oldContent = Data([0x01])
        try store.writeStateBaseline(romId: 1, slot: 0, baseline: StateSyncBaseline(
            serverId: 30, serverUpdatedAt: serverTime, contentHash: SaveContentHash.of(oldContent)
        ))
        try store.writeState(romId: 1, slot: 0, data: Data([0x02]))
        listStates.states = [makeState(id: 30, fileName: "slot0.state", updatedAt: serverTime)]

        _ = await makeCoordinator().syncSlot(romId: 1, slot: 0, emulator: "delta-ios")

        #expect(updateState.emulators == ["delta-ios"])
        #expect(uploadState.emulators.isEmpty)
    }

    /// Even when the server clock runs ahead and its differing content looks
    /// newer, the save the player just made is not replaced.
    @Test func pushAfterASaveNeverDownloadsOverIt() async throws {
        let now = Date()
        try store.writeStateBaseline(romId: 1, slot: 0, baseline: StateSyncBaseline(
            serverId: 30, serverUpdatedAt: now.addingTimeInterval(-3_600), contentHash: SaveContentHash.of(Data([0x01]))
        ))
        try store.writeState(romId: 1, slot: 0, data: Data([0x02]))
        listStates.states = [makeState(id: 30, fileName: "slot0.state", updatedAt: now.addingTimeInterval(3_600))]
        downloadState.data = Data([0x03])

        _ = await makeCoordinator().syncSlot(romId: 1, slot: 0, emulator: "delta-ios")

        #expect(try store.readState(romId: 1, slot: 0) == Data([0x02]))
    }

    @Test func pullReplacesTheThumbnailOfAnOverwrittenState() async throws {
        let now = Date()
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))
        try store.setStateModifiedAt(romId: 1, slot: 0, date: now.addingTimeInterval(-3_600))
        try store.writeThumbnail(romId: 1, slot: 0, data: Data([0xFF]))
        listStates.states = [makeState(id: 30, fileName: "slot0.state", updatedAt: now)]
        downloadState.data = Data([0x02])

        _ = await makeCoordinator().syncStates(romId: 1, mode: .pullOnly)

        #expect(try store.readState(romId: 1, slot: 0) == Data([0x02]))
        #expect(try store.readThumbnail(romId: 1, slot: 0) == nil)
    }

    @Test func failedCompareDownloadLeavesLocalStateAndBaselineAlone() async throws {
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))
        listStates.states = [makeState(id: 30, fileName: "slot0.state", updatedAt: Date())]

        let outcomes = await makeCoordinator().syncStates(romId: 1, mode: .bidirectional)

        guard case .failed = outcomes.first else { Issue.record("expected failure, got \(outcomes)"); return }
        #expect(try store.readState(romId: 1, slot: 0) == Data([0x01]))
        #expect(try store.readStateBaseline(romId: 1, slot: 0) == nil)
        #expect(uploadState.emulators.isEmpty)
    }

    @Test func pushDoesNotCreateASecondRowWhenTheServerCannotBeListed() async throws {
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))
        listStates.error = URLError(.timedOut)

        let outcome = await makeCoordinator().syncSlot(romId: 1, slot: 0, emulator: "delta-ios")

        guard case .failed = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(uploadState.emulators.isEmpty)
        #expect(updateState.emulators.isEmpty)
    }

    // MARK: - statusSummary

    @Test func statusSummaryReportsInSyncWhenNothingHasChanged() async throws {
        let now = Date()
        let content = Data([0x01])
        try store.writeState(romId: 1, slot: 0, data: content)
        try store.setStateModifiedAt(romId: 1, slot: 0, date: now)
        try store.writeStateBaseline(romId: 1, slot: 0, baseline: StateSyncBaseline(
            serverId: 30, serverUpdatedAt: now, contentHash: SaveContentHash.of(content)
        ))
        listStates.states = [makeState(id: 30, fileName: "slot0.state", updatedAt: now)]

        let status = await makeCoordinator().statusSummary(romId: 1)

        #expect(status == .inSync)
        #expect(uploadState.emulators.isEmpty)
        #expect(updateState.emulators.isEmpty)
    }

    @Test func statusSummaryReportsAPendingUploadForALocalOnlyState() async throws {
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))

        let status = await makeCoordinator().statusSummary(romId: 1)

        #expect(status == .pending(count: 1))
        #expect(uploadState.emulators.isEmpty)
    }

    @Test func statusSummaryReportsAPendingDownloadForAServerOnlyState() async throws {
        listStates.states = [makeState(id: 30, fileName: "slot0.state", updatedAt: Date())]

        let status = await makeCoordinator().statusSummary(romId: 1)

        #expect(status == .pending(count: 1))
        #expect(try store.readState(romId: 1, slot: 0) == nil)
        // A server-only slot is decided by first step alone: no content fetch needed.
        #expect(downloadState.callCount == 0)
    }

    /// A slot both sides touched since the last baseline cannot be told apart
    /// from "upload" or "download" without the server's content, which the
    /// peek never fetches: it counts as pending, same as any other change,
    /// and `syncSlot` (not this peek) is what actually resolves it.
    @Test func statusSummaryCountsANeedsServerContentSlotAsPendingWithoutFetchingIt() async throws {
        let baselineTime = Date(timeIntervalSince1970: 1_700_000_000)
        try store.writeStateBaseline(romId: 1, slot: 0, baseline: StateSyncBaseline(
            serverId: 30, serverUpdatedAt: baselineTime, contentHash: SaveContentHash.of(Data([0x00]))
        ))
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))
        try store.setStateModifiedAt(romId: 1, slot: 0, date: baselineTime.addingTimeInterval(3_600))
        listStates.states = [makeState(id: 30, fileName: "slot0.state", updatedAt: baselineTime.addingTimeInterval(7_200))]

        let status = await makeCoordinator().statusSummary(romId: 1)

        #expect(status == .pending(count: 1))
        #expect(downloadState.callCount == 0)
        #expect(try store.readState(romId: 1, slot: 0) == Data([0x01]))
        #expect(try store.readStateBaseline(romId: 1, slot: 0)?.serverId == 30)
    }

    @Test func statusSummaryReportsUnavailableWhenListingFailsAndALocalStateExists() async throws {
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))
        listStates.error = URLError(.timedOut)

        let status = await makeCoordinator().statusSummary(romId: 1)

        #expect(status == .unavailable)
    }

    @Test func statusSummaryReportsUnavailableWhenListingFailsWithNoLocalStateEither() async throws {
        listStates.error = URLError(.timedOut)

        let status = await makeCoordinator().statusSummary(romId: 1)

        #expect(status == .unavailable)
    }
}
