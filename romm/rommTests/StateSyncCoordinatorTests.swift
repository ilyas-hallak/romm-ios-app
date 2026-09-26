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
    func execute(id: Int) async throws -> Data { throw URLError(.fileDoesNotExist) }
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
            downloadStateUseCase: DownloadStateStub()
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

    @Test func pushDoesNotCreateASecondRowWhenTheServerCannotBeListed() async throws {
        try store.writeState(romId: 1, slot: 0, data: Data([0x01]))
        listStates.error = URLError(.timedOut)

        let outcome = await makeCoordinator().syncSlot(romId: 1, slot: 0, emulator: "delta-ios")

        guard case .failed = outcome else { Issue.record("expected failure, got \(outcome)"); return }
        #expect(uploadState.emulators.isEmpty)
        #expect(updateState.emulators.isEmpty)
    }
}
