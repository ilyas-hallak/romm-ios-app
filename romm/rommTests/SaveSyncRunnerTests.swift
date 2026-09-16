import Testing
import Foundation
@testable import romm

// MARK: - Fakes

private final class FakeUploadSaveUseCase: PUploadSaveUseCase, @unchecked Sendable {
    var errorForRomId: [Int: Error] = [:]
    private(set) var calls: [(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, fileName: String, fileData: Data)] = []
    private var nextId = 1000

    func execute(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        if let error = errorForRomId[romId] { throw error }
        calls.append((romId, emulator, slot, deviceId, sessionId, autocleanup, fileName, fileData))
        nextId += 1
        return Self.makeSchema(id: nextId, romId: romId, fileName: fileName)
    }

    static func makeSchema(
        id: Int, romId: Int, fileName: String, updatedAt: Date = Date(),
        slot: String? = nil, contentHash: String? = nil
    ) -> SaveSchema {
        SaveSchema(
            id: id, romId: romId, userId: 1, fileName: fileName, fileNameNoTags: fileName,
            fileNameNoExt: fileName, fileExtension: "sav", filePath: "", fileSizeBytes: 0,
            fullPath: "", downloadPath: "", missingFromFs: false, createdAt: updatedAt,
            updatedAt: updatedAt, emulator: nil, screenshot: nil, slot: slot, contentHash: contentHash
        )
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
        return FakeUploadSaveUseCase.makeSchema(id: id, romId: 0, fileName: "battery.sav")
    }
}

/// Only exercised by the external-upload freshness gate now; battery upload
/// and download are resolved from the plan itself (see `SyncPreviewOperation`).
private final class FakeListServerSavesUseCase: PListServerSavesUseCase, @unchecked Sendable {
    var savesByRomId: [Int: [SaveSchema]] = [:]
    private(set) var requestedRomIds: [Int] = []

    func execute(romId: Int) async throws -> [SaveSchema] {
        requestedRomIds.append(romId)
        return savesByRomId[romId] ?? []
    }
}

private final class FakeListServerStatesUseCase: PListServerStatesUseCase, @unchecked Sendable {
    var statesByRomId: [Int: [StateSchema]] = [:]
    var errorForRomId: [Int: Error] = [:]

    func execute(romId: Int) async throws -> [StateSchema] {
        if let error = errorForRomId[romId] { throw error }
        return statesByRomId[romId] ?? []
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

private final class FakeUploadStateUseCase: PUploadStateUseCase, @unchecked Sendable {
    private(set) var calls: [(romId: Int, fileName: String, fileData: Data)] = []
    private var nextId = 2000

    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        calls.append((romId, fileName, fileData))
        nextId += 1
        return FakeListServerStatesUseCase.makeSchema(id: nextId, romId: romId, fileName: fileName, updatedAt: Date())
    }
}

/// Not exercised by any scenario here. Trapping on a call would fail the test
/// loudly rather than silently accepting an unplanned state sync.
private final class UnusedUpdateStateUseCase: PUpdateStateUseCase, @unchecked Sendable {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        fatalError("not used in these tests")
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

private final class FakeCompleteSyncSessionUseCase: PCompleteSyncSessionUseCase, @unchecked Sendable {
    var error: Error?
    private(set) var calls: [(sessionId: String, operationsCompleted: Int, operationsFailed: Int)] = []

    func execute(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {
        calls.append((sessionId, operationsCompleted, operationsFailed))
        if let error { throw error }
    }
}

/// Grants a plain (non security-scoped) folder so tests can put files on disk
/// without needing a real user-picked bookmark.
private final class FakeExternalSaveFolderStore: PExternalSaveFolderStore, @unchecked Sendable {
    var grantsByEmulator: [ExternalEmulatorID: URL] = [:]

    func remember(folderURL: URL, for emulator: ExternalEmulatorID) throws {
        grantsByEmulator[emulator] = folderURL
    }
    func grantedFolder(for emulator: ExternalEmulatorID) -> ExternalSaveFolderGrant? {
        guard let url = grantsByEmulator[emulator] else { return nil }
        return ExternalSaveFolderGrant(url: url, isStale: false, scoped: false)
    }
    func forget(_ emulator: ExternalEmulatorID) {
        grantsByEmulator[emulator] = nil
    }
    func grantedEmulators() -> [ExternalEmulatorID] { Array(grantsByEmulator.keys) }
}

// MARK: - Tests

@MainActor
struct SaveSyncRunnerTests {

    private func makeStore() -> LocalSaveStoreRepository {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveSyncRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return LocalSaveStoreRepository(rootDirectory: tmp)
    }

    private func uploadOp(romId: Int, serverUpdatedAt: Date? = nil) -> SyncPreviewOperation {
        SyncPreviewOperation(
            romId: romId, direction: .upload, serverFileName: nil,
            slot: nil, emulator: nil, reason: nil, serverUpdatedAt: serverUpdatedAt
        )
    }

    private func downloadOp(
        romId: Int, serverFileName: String? = nil, serverUpdatedAt: Date?,
        saveId: Int?, serverContentHash: String? = nil
    ) -> SyncPreviewOperation {
        SyncPreviewOperation(
            romId: romId, direction: .download, serverFileName: serverFileName,
            slot: SaveSlot.battery, emulator: nil, reason: nil, serverUpdatedAt: serverUpdatedAt,
            saveId: saveId, serverContentHash: serverContentHash
        )
    }

    private func conflictOp(romId: Int) -> SyncPreviewOperation {
        SyncPreviewOperation(
            romId: romId, direction: .conflict, serverFileName: nil,
            slot: nil, emulator: nil, reason: "Both sides changed", serverUpdatedAt: nil
        )
    }

    private struct Fakes {
        let uploadSave = FakeUploadSaveUseCase()
        let downloadSave = FakeDownloadSaveUseCase()
        let confirmDownload = FakeConfirmSaveDownloadUseCase()
        let listSaves = FakeListServerSavesUseCase()
        let listStates = FakeListServerStatesUseCase()
        let uploadState = FakeUploadStateUseCase()
        let downloadState = FakeDownloadStateUseCase()
        let completeSession = FakeCompleteSyncSessionUseCase()
        let folderStore = FakeExternalSaveFolderStore()
    }

    private func makeRunner(store: PSaveStore, fakes: Fakes) -> SaveSyncRunner {
        SaveSyncRunner(
            saveStore: store,
            uploadSaveUseCase: fakes.uploadSave,
            downloadSaveUseCase: fakes.downloadSave,
            confirmSaveDownloadUseCase: fakes.confirmDownload,
            listServerSavesUseCase: fakes.listSaves,
            listServerStatesUseCase: fakes.listStates,
            uploadStateUseCase: fakes.uploadState,
            updateStateUseCase: UnusedUpdateStateUseCase(),
            downloadStateUseCase: fakes.downloadState,
            completeSyncSessionUseCase: fakes.completeSession,
            externalSaveFolderStore: fakes.folderStore
        )
    }

    // MARK: - Upload is device-scoped

    /// The plan lists every device's planned operations (see SyncPreview), so
    /// an upload for a ROM this device never wrote a battery save for must be
    /// skipped rather than executed as if it were this device's own change.
    @Test func skipsAnUploadWhenThisDeviceHasNoLocalBatteryFile() async throws {
        let store = makeStore()
        let fakes = Fakes()

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [uploadOp(romId: 42)])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.skipped == 1)
        #expect(report.uploaded == 0)
        #expect(report.failed == 0)
        #expect(fakes.uploadSave.calls.isEmpty)
    }

    /// Even with a local file present, a plan computed against a server state
    /// newer than this device's own copy must not be pushed: it is not this
    /// device's change to make.
    @Test func skipsAnUploadWhenThisDevicesCopyIsOlderThanThePlannedServerState() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 7, data: Data([0x01]))
        let oldLocalTime = Date(timeIntervalSince1970: 1_600_000_000)
        try store.setBatteryModifiedAt(romId: 7, date: oldLocalTime)
        let fakes = Fakes()

        let newerServerTime = Date(timeIntervalSince1970: 1_700_000_000)
        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 1, operations: [uploadOp(romId: 7, serverUpdatedAt: newerServerTime)])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.skipped == 1)
        #expect(fakes.uploadSave.calls.isEmpty)
    }

    // MARK: - Battery upload sends device/session bookkeeping

    /// Every upload carries this device's id, the session negotiate opened
    /// (when there is one), and `autocleanup=true`; the server is the one
    /// that dedups and prunes now (see the sync API spec), not the client.
    @Test func uploadSendsDeviceIdSessionIdAndAutocleanup() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xCA, 0xFE]))
        let fakes = Fakes()

        let preview = SyncPreview(deviceId: "device-42", reportedSaveCount: 1, operations: [uploadOp(romId: 1)], sessionId: "session-9")
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.uploaded == 1)
        #expect(fakes.uploadSave.calls.first?.deviceId == "device-42")
        #expect(fakes.uploadSave.calls.first?.sessionId == "session-9")
        #expect(fakes.uploadSave.calls.first?.autocleanup == true)
    }

    /// HTTP 409 means the slot moved on the server since this device's last
    /// sync (the `overwrite` guard, see the sync API spec). Not a failure:
    /// it lands alongside the conflicts negotiate already flagged.
    @Test func uploadConflictLandsInSkippedConflictsNotFailed() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xCA, 0xFE]))
        let fakes = Fakes()
        fakes.uploadSave.errorForRomId[1] = APIClientError.conflict("slot moved")

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 1, operations: [uploadOp(romId: 1)])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.skippedConflicts == 1)
        #expect(report.failed == 0)
        #expect(report.uploaded == 0)
    }

    // MARK: - Battery download is resolved by save id

    /// The plan carries the save's id directly (see `SyncPreviewOperation`),
    /// so the download goes straight to it rather than matching a file name
    /// against a freshly fetched list: two saves for the same ROM can share
    /// a name.
    @Test func downloadResolvedBySaveIdNotFilename() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.downloadSave.dataForId[9] = Data([0x01, 0x02, 0x03])

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 0,
            operations: [downloadOp(romId: 2, serverUpdatedAt: serverTime, saveId: 9)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.downloaded == 1)
        #expect(fakes.downloadSave.calls.map(\.id) == [9])
        #expect(try store.readBattery(romId: 2) == Data([0x01, 0x02, 0x03]))
    }

    /// A plan entry with no save id (an older server, or one that could not
    /// resolve one) cannot be downloaded at all: there is nothing to fetch.
    @Test func downloadSkippedWhenSaveIdIsMissing() async throws {
        let store = makeStore()
        let fakes = Fakes()

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 0,
            operations: [downloadOp(romId: 2, serverUpdatedAt: Date(), saveId: nil)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.skipped == 1)
        #expect(report.downloaded == 0)
        #expect(fakes.downloadSave.calls.isEmpty)
    }

    /// A clock-skewed write can make the server's copy look newer even though
    /// its bytes are identical to what is already on disk locally. Content
    /// beats timestamp, using the hash the plan already carries rather than
    /// refetching the save just to compare it.
    @Test func downloadSkipsWhenPlanContentHashMatchesDespiteANewerServerTimestamp() async throws {
        let store = makeStore()
        let data = Data([0xAA, 0xBB])
        try store.writeBattery(romId: 2, data: data)
        let oldLocalTime = Date(timeIntervalSince1970: 1_700_000_000)
        try store.setBatteryModifiedAt(romId: 2, date: oldLocalTime)
        let fakes = Fakes()
        let newerServerTime = oldLocalTime.addingTimeInterval(3600)
        let matchingHash = CloudSaveSyncService.contentHash(data)

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 0,
            operations: [downloadOp(romId: 2, serverUpdatedAt: newerServerTime, saveId: 9, serverContentHash: matchingHash)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.skipped == 1)
        #expect(report.downloaded == 0)
        #expect(fakes.downloadSave.calls.isEmpty)
        #expect(try store.readBattery(romId: 2) == data)
    }

    /// When the plan carries no content hash at all (an older, un-hashed
    /// save), the timestamp comparison is still the only signal available.
    @Test func downloadFallsBackToTimestampComparisonWhenNoContentHashIsAvailable() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 2, data: Data([0xAA]))
        let oldLocalTime = Date(timeIntervalSince1970: 1_700_000_000)
        try store.setBatteryModifiedAt(romId: 2, date: oldLocalTime)
        let fakes = Fakes()
        let newerServerTime = oldLocalTime.addingTimeInterval(3600)
        fakes.downloadSave.dataForId[9] = Data([0x01, 0x02, 0x03])

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 0,
            operations: [downloadOp(romId: 2, serverUpdatedAt: newerServerTime, saveId: 9)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.downloaded == 1)
        #expect(try store.readBattery(romId: 2) == Data([0x01, 0x02, 0x03]))
    }

    /// Writes the downloaded save locally and adopts the server's timestamp,
    /// so a later comparison is not skewed by clock drift after the write.
    @Test func downloadWritesLocallyAndAdoptsTheServerTimestamp() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.downloadSave.dataForId[9] = Data([0x01, 0x02, 0x03])

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 0,
            operations: [downloadOp(romId: 2, serverUpdatedAt: serverTime, saveId: 9)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.downloaded == 1)
        #expect(try store.readBattery(romId: 2) == Data([0x01, 0x02, 0x03]))
        #expect(store.batteryModifiedAt(romId: 2) == serverTime)
    }

    /// The screen keeps its loaded plan across a leave-and-return, so an
    /// automatic push can have written a newer local battery in the meantime.
    /// The download must not clobber it.
    @Test func downloadSkipsWhenTheLocalCopyIsNewerThanTheServer() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 2, data: Data([0xAA]))
        let newLocalTime = Date(timeIntervalSince1970: 1_750_000_000)
        try store.setBatteryModifiedAt(romId: 2, date: newLocalTime)

        let fakes = Fakes()
        let staleServerTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.downloadSave.dataForId[9] = Data([0x01, 0x02, 0x03])

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 1,
            operations: [downloadOp(romId: 2, serverUpdatedAt: staleServerTime, saveId: 9)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.skipped == 1)
        #expect(report.downloaded == 0)
        #expect(try store.readBattery(romId: 2) == Data([0xAA]))
        #expect(fakes.downloadSave.calls.isEmpty)
    }

    // MARK: - Download confirmation

    /// A successful download is followed by a confirmation to the server,
    /// naming this device, so negotiate stops re-planning the same download.
    @Test func downloadSendsConfirmationWithTheDeviceId() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.downloadSave.dataForId[9] = Data([0x01])

        let preview = SyncPreview(
            deviceId: "device-7", reportedSaveCount: 0,
            operations: [downloadOp(romId: 2, serverUpdatedAt: serverTime, saveId: 9)]
        )
        _ = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(fakes.confirmDownload.calls.count == 1)
        #expect(fakes.confirmDownload.calls.first?.id == 9)
        #expect(fakes.confirmDownload.calls.first?.deviceId == "device-7")
    }

    /// The confirmation is best-effort bookkeeping: a failure there never
    /// undoes the download that already succeeded and was already written.
    @Test func failedConfirmationStillCountsTheDownloadAsSuccessful() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.downloadSave.dataForId[9] = Data([0x01])
        fakes.confirmDownload.error = URLError(.notConnectedToInternet)

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 0,
            operations: [downloadOp(romId: 2, serverUpdatedAt: serverTime, saveId: 9)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.downloaded == 1)
        #expect(report.failed == 0)
        #expect(try store.readBattery(romId: 2) == Data([0x01]))
    }

    // MARK: - Conflicts

    /// Conflicts are only counted, never acted on: neither side can be
    /// preferred automatically.
    @Test func conflictsAreSkippedAndOnlyCounted() async throws {
        let store = makeStore()
        let fakes = Fakes()

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [conflictOp(romId: 3)])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.skippedConflicts == 1)
        #expect(report.uploaded == 0)
        #expect(report.downloaded == 0)
        #expect(fakes.uploadSave.calls.isEmpty)
    }

    // MARK: - One failure does not abort the run

    @Test func oneUploadsFailureDoesNotStopTheOthers() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 10, data: Data([0xAA]))
        try store.writeBattery(romId: 11, data: Data([0xBB]))
        let fakes = Fakes()
        fakes.uploadSave.errorForRomId[10] = URLError(.timedOut)

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 2,
            operations: [uploadOp(romId: 10), uploadOp(romId: 11)]
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.failed == 1)
        #expect(report.uploaded == 1)
        #expect(report.errors.count == 1)
        #expect(fakes.uploadSave.calls.map(\.romId) == [11])
    }

    // MARK: - Save states

    /// Negotiate never plans states (see SyncPreviewUseCase), so this is the
    /// only path that ever syncs them: a state this device has and the server
    /// does not is uploaded under its own slot.
    @Test func stateSyncUploadsALocalOnlyState() async throws {
        let store = makeStore()
        try store.writeState(romId: 5, slot: 0, data: Data([0x10]))
        let fakes = Fakes()

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.uploaded == 1)
        #expect(fakes.uploadState.calls.count == 1)
        #expect(fakes.uploadState.calls.first?.romId == 5)
    }

    /// A state the server has and this device does not is downloaded into the
    /// same slot the server reports it under.
    @Test func stateSyncDownloadsAServerOnlyState() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let serverTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.listStates.statesByRomId[6] = [
            FakeListServerStatesUseCase.makeSchema(id: 30, romId: 6, fileName: "slot0.state", updatedAt: serverTime)
        ]
        fakes.downloadState.dataForId[30] = Data([0x20, 0x21])
        // The runner still needs a reason to look at ROM 6 at all: a local
        // battery file is enough to put it in listRomIds() without also
        // creating a local state.
        try store.writeBattery(romId: 6, data: Data([0x01]))

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.downloaded == 1)
        #expect(fakes.downloadState.requestedIds == [30])
        #expect(try store.readState(romId: 6, slot: 0) == Data([0x20, 0x21]))
    }

    // MARK: - External emulator apps

    /// Reads through the folder store's grant, and only uploads when the file
    /// is newer than what the server already holds for that ROM. Still needs
    /// `listServerSavesUseCase` for this freshness gate, unlike battery sync.
    @Test func uploadsAnExternalFileOnlyWhenNewerThanTheServerSave() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fakes.folderStore.grantsByEmulator[.retroarch] = folder

        let staleServerTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.listSaves.savesByRomId[20] = [FakeUploadSaveUseCase.makeSchema(id: 1, romId: 20, fileName: "a.srm", updatedAt: staleServerTime)]
        fakes.listSaves.savesByRomId[21] = [FakeUploadSaveUseCase.makeSchema(id: 2, romId: 21, fileName: "b.srm", updatedAt: staleServerTime)]

        let olderFile = folder.appendingPathComponent("older.srm")
        let newerFile = folder.appendingPathComponent("newer.srm")
        try Data([0x01]).write(to: olderFile)
        try Data([0x02]).write(to: newerFile)

        let scans: [ExternalEmulatorID: ExternalSaveScan] = [
            .retroarch: ExternalSaveScan(
                emulator: .retroarch,
                matched: [
                    ExternalSaveFile(
                        candidate: ExternalSaveCandidate(
                            url: olderFile, fileName: "older.srm",
                            sizeBytes: 1, modifiedAt: staleServerTime.addingTimeInterval(-3600)
                        ),
                        romId: 20
                    ),
                    ExternalSaveFile(
                        candidate: ExternalSaveCandidate(
                            url: newerFile, fileName: "newer.srm",
                            sizeBytes: 1, modifiedAt: staleServerTime.addingTimeInterval(3600)
                        ),
                        romId: 21
                    )
                ],
                unmatchedFileNames: [],
                isStale: false
            )
        ]

        let preview = SyncPreview(deviceId: "device-3", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: scans)

        #expect(report.uploaded == 1)
        #expect(fakes.uploadSave.calls.count == 1)
        #expect(fakes.uploadSave.calls.first?.romId == 21)
        #expect(fakes.uploadSave.calls.first?.slot == SaveSlot.battery)
        #expect(fakes.uploadSave.calls.first?.emulator == ExternalEmulatorID.retroarch.rawValue)
        #expect(fakes.uploadSave.calls.first?.deviceId == "device-3")
        #expect(fakes.uploadSave.calls.first?.autocleanup == true)
    }

    /// External saves were never part of the negotiated plan, so unlike a
    /// battery upload this must never carry the session id negotiate opened,
    /// even though the run itself does have one.
    @Test func externalUploadSendsNoSessionIdButKeepsDeviceIdAndAutocleanup() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fakes.folderStore.grantsByEmulator[.retroarch] = folder

        let file = folder.appendingPathComponent("a.srm")
        try Data([0x01]).write(to: file)

        let scans: [ExternalEmulatorID: ExternalSaveScan] = [
            .retroarch: ExternalSaveScan(
                emulator: .retroarch,
                matched: [ExternalSaveFile(
                    candidate: ExternalSaveCandidate(url: file, fileName: "a.srm", sizeBytes: 1, modifiedAt: Date()),
                    romId: 30
                )],
                unmatchedFileNames: [],
                isStale: false
            )
        ]

        let preview = SyncPreview(deviceId: "device-9", reportedSaveCount: 0, operations: [], sessionId: "session-1")
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: scans)

        #expect(report.uploaded == 1)
        #expect(fakes.uploadSave.calls.first?.sessionId == nil)
        #expect(fakes.uploadSave.calls.first?.deviceId == "device-9")
        #expect(fakes.uploadSave.calls.first?.autocleanup == true)
    }

    /// Several matched files can point at the same ROM (across one app's
    /// folder, or even different apps). The server save list for that ROM is
    /// only fetched once per run, not once per matched file.
    @Test func externalUploadsFetchTheServerSaveListOnlyOncePerRom() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fakes.folderStore.grantsByEmulator[.retroarch] = folder

        let staleServerTime = Date(timeIntervalSince1970: 1_700_000_000)
        fakes.listSaves.savesByRomId[40] = [FakeUploadSaveUseCase.makeSchema(id: 1, romId: 40, fileName: "a.srm", updatedAt: staleServerTime)]

        let fileA = folder.appendingPathComponent("a.srm")
        let fileB = folder.appendingPathComponent("b.srm")
        try Data([0x01]).write(to: fileA)
        try Data([0x02]).write(to: fileB)

        let scans: [ExternalEmulatorID: ExternalSaveScan] = [
            .retroarch: ExternalSaveScan(
                emulator: .retroarch,
                matched: [
                    ExternalSaveFile(
                        candidate: ExternalSaveCandidate(url: fileA, fileName: "a.srm", sizeBytes: 1, modifiedAt: staleServerTime.addingTimeInterval(3600)),
                        romId: 40
                    ),
                    ExternalSaveFile(
                        candidate: ExternalSaveCandidate(url: fileB, fileName: "b.srm", sizeBytes: 1, modifiedAt: staleServerTime.addingTimeInterval(3600)),
                        romId: 40
                    )
                ],
                unmatchedFileNames: [],
                isStale: false
            )
        ]

        let preview = SyncPreview(deviceId: "device-9", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: scans)

        #expect(report.uploaded == 2)
        #expect(fakes.listSaves.requestedRomIds == [40])
    }

    /// The same 409 handling battery uploads get applies here too: the check
    /// sits right after the upload call itself, regardless of which path
    /// triggered it.
    @Test func externalUploadConflictLandsInSkippedConflictsNotFailed() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fakes.folderStore.grantsByEmulator[.retroarch] = folder
        fakes.uploadSave.errorForRomId[50] = APIClientError.conflict("slot moved")

        let file = folder.appendingPathComponent("a.srm")
        try Data([0x01]).write(to: file)

        let scans: [ExternalEmulatorID: ExternalSaveScan] = [
            .retroarch: ExternalSaveScan(
                emulator: .retroarch,
                matched: [ExternalSaveFile(
                    candidate: ExternalSaveCandidate(url: file, fileName: "a.srm", sizeBytes: 1, modifiedAt: Date()),
                    romId: 50
                )],
                unmatchedFileNames: [],
                isStale: false
            )
        ]

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: scans)

        #expect(report.skippedConflicts == 1)
        #expect(report.failed == 0)
        #expect(report.uploaded == 0)
    }

    /// A matched file can vanish between the scan and the run (the external
    /// app deletes or renames it, its folder unmounts, ...): reading it inside
    /// the security scope then throws. That must fail cleanly for just this
    /// file, without stopping the rest of the run.
    @Test func externalUploadReadFailureIsReportedAsFailureWithoutAbortingTheRun() async throws {
        let store = makeStore()
        let fakes = Fakes()
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fakes.folderStore.grantsByEmulator[.retroarch] = folder

        let missingFile = folder.appendingPathComponent("gone.srm")
        let okFile = folder.appendingPathComponent("b.srm")
        try Data([0x02]).write(to: okFile)
        // `missingFile` is never written, so `Data(contentsOf:)` throws when
        // the runner tries to read it.

        let scans: [ExternalEmulatorID: ExternalSaveScan] = [
            .retroarch: ExternalSaveScan(
                emulator: .retroarch,
                matched: [
                    ExternalSaveFile(
                        candidate: ExternalSaveCandidate(url: missingFile, fileName: "gone.srm", sizeBytes: 1, modifiedAt: Date()),
                        romId: 60
                    ),
                    ExternalSaveFile(
                        candidate: ExternalSaveCandidate(url: okFile, fileName: "b.srm", sizeBytes: 1, modifiedAt: Date()),
                        romId: 61
                    )
                ],
                unmatchedFileNames: [],
                isStale: false
            )
        ]

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: scans)

        #expect(report.failed == 1)
        #expect(report.uploaded == 1)
        #expect(fakes.uploadSave.calls.map(\.romId) == [61])
    }

    // MARK: - Save states, server listing failures

    /// Every ROM this device holds anything for is checked for states each
    /// run, including one this device only ever wrote a battery save for (see
    /// `run`'s `listRomIds` loop). When listing that ROM's server states then
    /// fails, there is no local state to protect, so the failure is dropped
    /// rather than surfaced.
    @Test func stateSyncDropsTheFailureSilentlyWhenThisDeviceHasNoLocalStatesForThatRom() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 70, data: Data([0x01]))
        let fakes = Fakes()
        fakes.listStates.errorForRomId[70] = URLError(.notConnectedToInternet)

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.failed == 0)
        #expect(report.errors.isEmpty)
    }

    /// The same listing failure, but for a ROM this device does hold a local
    /// state for: now there is something that could silently fall out of
    /// sync, so it must show up as one failed outcome instead of being
    /// dropped.
    @Test func stateSyncReportsOneFailureWhenThisDeviceHasALocalStateForThatRom() async throws {
        let store = makeStore()
        try store.writeState(romId: 71, slot: 0, data: Data([0x02]))
        let fakes = Fakes()
        fakes.listStates.errorForRomId[71] = URLError(.notConnectedToInternet)

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 0, operations: [])
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.failed == 1)
        #expect(report.errors.count == 1)
        #expect(fakes.uploadState.calls.isEmpty)
    }

    // MARK: - Sync session bookkeeping

    /// Closing the session is the server's own bookkeeping (see
    /// `CompleteSyncSessionUseCase`), done once at the end of the run with
    /// the totals this run actually produced.
    @Test func sessionIsCompletedWithTheRunsCountersAtTheEnd() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xCA]))
        try store.writeBattery(romId: 2, data: Data([0xFE]))
        let fakes = Fakes()
        fakes.uploadSave.errorForRomId[2] = URLError(.timedOut)

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 2,
            operations: [uploadOp(romId: 1), uploadOp(romId: 2)],
            sessionId: "session-1"
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(fakes.completeSession.calls.count == 1)
        #expect(fakes.completeSession.calls.first?.sessionId == "session-1")
        #expect(fakes.completeSession.calls.first?.operationsCompleted == report.uploaded + report.downloaded)
        #expect(fakes.completeSession.calls.first?.operationsFailed == report.failed)
    }

    /// States (never part of the negotiate plan, see `SyncPreviewUseCase`)
    /// and external-app uploads (never negotiated at all) still show up in
    /// the returned `SaveSyncReport`, but must not inflate the count reported
    /// back to the session negotiate opened: that count is only the
    /// negotiated battery uploads/downloads this run actually carried out.
    @Test func sessionCompletionCountsOnlyNegotiatedBatteryOperations() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xCA]))
        // A local-only state for a different ROM: not part of the plan, but
        // still picked up and uploaded by the unconditional state sync.
        try store.writeState(romId: 5, slot: 0, data: Data([0x10]))
        let fakes = Fakes()

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalFolder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fakes.folderStore.grantsByEmulator[.retroarch] = folder
        let externalFile = folder.appendingPathComponent("a.srm")
        try Data([0x01]).write(to: externalFile)
        let scans: [ExternalEmulatorID: ExternalSaveScan] = [
            .retroarch: ExternalSaveScan(
                emulator: .retroarch,
                matched: [ExternalSaveFile(
                    candidate: ExternalSaveCandidate(url: externalFile, fileName: "a.srm", sizeBytes: 1, modifiedAt: Date()),
                    romId: 99
                )],
                unmatchedFileNames: [],
                isStale: false
            )
        ]

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 1,
            operations: [uploadOp(romId: 1)],
            sessionId: "session-1"
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: scans)

        // The report itself does count everything: 1 battery upload, 1 state
        // upload, 1 external upload.
        #expect(report.uploaded == 3)
        // But the session only ever heard about the one negotiated op.
        #expect(fakes.completeSession.calls.count == 1)
        #expect(fakes.completeSession.calls.first?.operationsCompleted == 1)
        #expect(fakes.completeSession.calls.first?.operationsFailed == 0)
    }

    /// A server too old to open a session (see `SyncPreview.sessionId`) never
    /// gets a completion call: there is nothing to close.
    @Test func sessionIsNotCompletedWhenThePreviewCarriesNoSessionId() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xCA]))
        let fakes = Fakes()

        let preview = SyncPreview(deviceId: "d1", reportedSaveCount: 1, operations: [uploadOp(romId: 1)])
        _ = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(fakes.completeSession.calls.isEmpty)
    }

    /// Closing the session is only the server's own bookkeeping (see the
    /// `run` doc comment), done after the report is already final. A hiccup
    /// there must not turn an otherwise successful run into a failed one.
    @Test func sessionCompletionFailureDoesNotAffectTheReport() async throws {
        let store = makeStore()
        try store.writeBattery(romId: 1, data: Data([0xCA]))
        let fakes = Fakes()
        fakes.completeSession.error = URLError(.notConnectedToInternet)

        let preview = SyncPreview(
            deviceId: "d1", reportedSaveCount: 1,
            operations: [uploadOp(romId: 1)],
            sessionId: "session-1"
        )
        let report = await makeRunner(store: store, fakes: fakes).run(preview: preview, externalScans: [:])

        #expect(report.uploaded == 1)
        #expect(report.failed == 0)
        #expect(fakes.completeSession.calls.count == 1)
    }
}
