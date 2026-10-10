import Testing
import Foundation
@testable import romm

struct GetLocalDataSummaryUseCaseTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LogoutTests-\(UUID().uuidString)", isDirectory: true)

    private func makeUseCase(
        roms: [DownloadedROM] = [],
        lastSyncByRomId: [Int: Date] = [:]
    ) -> (GetLocalDataSummaryUseCase, LocalSaveStoreRepository) {
        let store = LocalSaveStoreRepository(rootDirectory: root)
        let useCase = GetLocalDataSummaryUseCase(
            localROMRepository: RecordingLocalROMs(roms: roms),
            saveStore: store,
            syncStore: FixedSyncStore(lastSyncByRomId: lastSyncByRomId)
        )
        return (useCase, store)
    }

    @Test func countsDownloadedROMsAndTheirSize() throws {
        let (useCase, _) = makeUseCase(roms: [rom(1, bytes: 1_000), rom(2, bytes: 2_500)])

        let summary = try useCase.execute()

        #expect(summary == LocalDataSummary(downloadedROMCount: 2, downloadedBytes: 3_500, gamesWithUnsyncedSaves: 0))
    }

    @Test func batterySaveWithoutAnyRecordedSyncIsUnsynced() throws {
        let (useCase, store) = makeUseCase()
        try store.writeBattery(romId: 7, data: Data([1, 2, 3]))

        #expect(try useCase.execute().gamesWithUnsyncedSaves == 1)
    }

    @Test func batterySaveWrittenAfterTheLastSyncIsUnsynced() throws {
        let (useCase, store) = makeUseCase(lastSyncByRomId: [7: Date(timeIntervalSince1970: 1_000)])
        try store.writeBattery(romId: 7, data: Data([1, 2, 3]))
        try store.setBatteryModifiedAt(romId: 7, date: Date(timeIntervalSince1970: 2_000))

        #expect(try useCase.execute().gamesWithUnsyncedSaves == 1)
    }

    @Test func batterySaveOlderThanTheLastSyncIsSynced() throws {
        let (useCase, store) = makeUseCase(lastSyncByRomId: [7: Date(timeIntervalSince1970: 2_000)])
        try store.writeBattery(romId: 7, data: Data([1, 2, 3]))
        try store.setBatteryModifiedAt(romId: 7, date: Date(timeIntervalSince1970: 1_000))

        #expect(try useCase.execute().gamesWithUnsyncedSaves == 0)
    }

    @Test func stateMatchingItsBaselineIsSynced() throws {
        let (useCase, store) = makeUseCase()
        let data = Data([9, 9, 9])
        try store.writeState(romId: 3, slot: 1, data: data)
        try store.writeStateBaseline(romId: 3, slot: 1, baseline: baseline(for: data))

        #expect(try useCase.execute().gamesWithUnsyncedSaves == 0)
    }

    @Test func stateChangedSinceItsBaselineIsUnsynced() throws {
        let (useCase, store) = makeUseCase()
        try store.writeState(romId: 3, slot: 1, data: Data([1]))
        try store.writeStateBaseline(romId: 3, slot: 1, baseline: baseline(for: Data([2])))

        #expect(try useCase.execute().gamesWithUnsyncedSaves == 1)
    }

    @Test func stateWithoutBaselineIsUnsynced() throws {
        let (useCase, store) = makeUseCase()
        try store.writeState(romId: 3, slot: 1, data: Data([1]))

        #expect(try useCase.execute().gamesWithUnsyncedSaves == 1)
    }

    @Test func countsGamesNotSaves() throws {
        let (useCase, store) = makeUseCase()
        try store.writeBattery(romId: 3, data: Data([1]))
        try store.writeState(romId: 3, slot: 1, data: Data([1]))
        try store.writeState(romId: 3, slot: 2, data: Data([2]))
        try store.writeState(romId: 4, slot: 1, data: Data([1]))

        #expect(try useCase.execute().gamesWithUnsyncedSaves == 2)
    }

    private func baseline(for data: Data) -> StateSyncBaseline {
        StateSyncBaseline(serverId: 1, serverUpdatedAt: Date(timeIntervalSince1970: 0), contentHash: SaveContentHash.of(data))
    }
}

struct DeleteLocalGameDataUseCaseTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("LogoutTests-\(UUID().uuidString)", isDirectory: true)

    @Test func deletesEveryDownloadedROM() throws {
        let repository = RecordingLocalROMs(roms: [rom(1), rom(2), rom(3)])
        let store = LocalSaveStoreRepository(rootDirectory: root)

        try DeleteLocalGameDataUseCase(localROMRepository: repository, saveStore: store).execute()

        #expect(repository.deletedIds == [1, 2, 3])
    }

    @Test func deletesSavesAndStatesIncludingUnsyncedOnes() throws {
        let store = LocalSaveStoreRepository(rootDirectory: root)
        try store.writeBattery(romId: 1, data: Data([1]))
        try store.writeState(romId: 2, slot: 1, data: Data([2]))

        try DeleteLocalGameDataUseCase(localROMRepository: RecordingLocalROMs(roms: []), saveStore: store).execute()

        #expect(try store.listRomIds().isEmpty)
        #expect(try store.readBattery(romId: 1) == nil)
        #expect(try store.listStates(romId: 2).isEmpty)
    }

    @Test func keepsGoingPastAFailureAndReportsIt() throws {
        let repository = RecordingLocalROMs(roms: [rom(1), rom(2), rom(3)], failingIds: [2])
        let store = LocalSaveStoreRepository(rootDirectory: root)
        try store.writeBattery(romId: 1, data: Data([1]))

        #expect(throws: (any Error).self) {
            try DeleteLocalGameDataUseCase(localROMRepository: repository, saveStore: store).execute()
        }
        #expect(repository.deletedIds == [1, 3])
        #expect(try store.listRomIds().isEmpty)
    }
}

@MainActor
struct LogoutMessageTests {
    @Test func namesCountAndSizeOfTheDownloadsAndThatSavesGoToo() {
        let summary = LocalDataSummary(downloadedROMCount: 30, downloadedBytes: 12_000_000_000, gamesWithUnsyncedSaves: 0)
        let size = ByteCountFormatter.string(fromByteCount: 12_000_000_000, countStyle: .file)

        #expect(ProfileViewModel.logoutMessage(for: summary) == "You have 30 ROMs (\(size)) downloaded on this device. "
            + "Deleting downloads also removes all saves and save states on this device.")
    }

    @Test func usesTheSingularForOneROM() {
        let summary = LocalDataSummary(downloadedROMCount: 1, downloadedBytes: 1_000, gamesWithUnsyncedSaves: 0)

        #expect(ProfileViewModel.logoutMessage(for: summary).hasPrefix("You have 1 ROM ("))
    }

    @Test func warnsThatDeletingLosesUnsyncedSaves() {
        let summary = LocalDataSummary(downloadedROMCount: 2, downloadedBytes: 1_000, gamesWithUnsyncedSaves: 3)

        #expect(ProfileViewModel.logoutMessage(for: summary).hasSuffix("\n\nWarning: 3 games have saves that are not synced "
            + "to the server yet. Deleting downloads deletes them for good."))
    }

    @Test func saysUnsyncedSavesStayWhenNothingCanBeDeleted() {
        let summary = LocalDataSummary(downloadedROMCount: 0, downloadedBytes: 0, gamesWithUnsyncedSaves: 1)

        #expect(ProfileViewModel.logoutMessage(for: summary) == "No ROMs are downloaded on this device.\n\n"
            + "1 game has saves that are not synced to the server yet. They stay on this device.")
    }
}

@MainActor
struct ProfileViewModelLogoutTests {
    private let factory = LogoutFactory()
    private let downloads = DownloadsSpy()
    private let center = NotificationCenter()

    private func makeViewModel() -> ProfileViewModel {
        ProfileViewModel(factory: factory, downloads: downloads, notificationCenter: center)
    }

    private struct RestartRequest {
        let notice: String?
    }

    /// Logs out and returns the restart request it posted, if any.
    private func logout(deletingDownloads: Bool) async -> RestartRequest? {
        var request: RestartRequest?
        let token = center.addObserver(forName: .restartSetupRequested, object: nil, queue: nil) {
            request = RestartRequest(notice: $0.userInfo?[RestartSetupNotice.userInfoKey] as? String)
        }
        defer { center.removeObserver(token) }
        await makeViewModel().logout(deletingDownloads: deletingDownloads)
        return request
    }

    @Test(arguments: [false, true])
    func stopsRunningDownloadsEitherWay(deletingDownloads: Bool) async {
        _ = await logout(deletingDownloads: deletingDownloads)

        #expect(downloads.cancelAllCalls == 1)
    }

    @Test func keepingDownloadsDeletesNothing() async {
        let request = await logout(deletingDownloads: false)

        #expect(factory.delete.calls == 0)
        #expect(factory.clearSetup.calls == 1)
        #expect(request != nil)
    }

    @Test func aCleanDeleteSignsOutWithoutANotice() async {
        let request = await logout(deletingDownloads: true)

        #expect(factory.delete.calls == 1)
        #expect(factory.clearSetup.calls == 1)
        #expect(request != nil)
        #expect(request?.notice == nil)
    }

    @Test func aFailedDeleteStillSignsOutAndLeavesANotice() async {
        factory.delete.error = DeleteFailed()

        let request = await logout(deletingDownloads: true)

        #expect(factory.clearSetup.calls == 1)
        #expect(request?.notice == "Some downloads or saves could not be deleted.")
    }

    @Test func anUnreadableSummaryStillAsksHowToLogOut() async {
        factory.summary.error = DeleteFailed()
        let viewModel = makeViewModel()

        await viewModel.prepareLogout()

        #expect(viewModel.logoutSummary == nil)
        #expect(viewModel.isLogoutConfirmationPresented)
        #expect(viewModel.logoutMessage == "You will be signed out and returned to the setup screen.")
    }
}

/// Swaps out everything logging out touches, so no test reaches the real
/// setup configuration, save store or download queue.
private final class LogoutFactory: MockDependencyFactory {
    let summary = SummaryStub()
    let delete = DeleteSpy()
    let clearSetup = ClearSetupSpy()

    override func makeGetLocalDataSummaryUseCase() -> PGetLocalDataSummaryUseCase { summary }
    override func makeDeleteLocalGameDataUseCase() -> PDeleteLocalGameDataUseCase { delete }
    override func makeClearSetupConfigurationUseCase() -> PClearSetupConfigurationUseCase { clearSetup }
    override func makeGetServerConnectionUseCase() -> PGetServerConnectionUseCase { NoServerConnection() }
}

private final class SummaryStub: PGetLocalDataSummaryUseCase, @unchecked Sendable {
    var error: Error?
    func execute() throws -> LocalDataSummary {
        if let error { throw error }
        return LocalDataSummary(downloadedROMCount: 0, downloadedBytes: 0, gamesWithUnsyncedSaves: 0)
    }
}

private final class DeleteSpy: PDeleteLocalGameDataUseCase, @unchecked Sendable {
    var error: Error?
    private(set) var calls = 0
    func execute() throws {
        calls += 1
        if let error { throw error }
    }
}

private final class ClearSetupSpy: PClearSetupConfigurationUseCase {
    private(set) var calls = 0
    func execute() throws { calls += 1 }
}

private struct NoServerConnection: PGetServerConnectionUseCase {
    func execute() -> ServerConnection? { nil }
}

private final class DownloadsSpy: PDownloadCancelling {
    private(set) var cancelAllCalls = 0
    func cancelAll() { cancelAllCalls += 1 }
}

private func rom(_ id: Int, bytes: Int64 = 0) -> DownloadedROM {
    DownloadedROM(
        id: id,
        name: "ROM \(id)",
        platformName: "Game Boy",
        platformSlug: "gb",
        downloadedAt: Date(),
        totalSizeBytes: bytes,
        localDirectory: "Game Boy/ROM \(id)",
        files: [],
        urlCover: nil
    )
}

private struct DeleteFailed: Error {}

private final class RecordingLocalROMs: PLocalROMRepository {
    let roms: [DownloadedROM]
    let failingIds: Set<Int>
    private(set) var deletedIds: [Int] = []
    var romsBaseURL: URL { FileManager.default.temporaryDirectory }

    init(roms: [DownloadedROM], failingIds: Set<Int> = []) {
        self.roms = roms
        self.failingIds = failingIds
    }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { roms }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { roms.first { $0.id == id } }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {
        if failingIds.contains(rom.id) { throw DeleteFailed() }
        deletedIds.append(rom.id)
    }
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { roms.count }
}

private struct FixedSyncStore: PCloudSaveSyncStore {
    let lastSyncByRomId: [Int: Date]

    func recordSync(romId: Int, trigger: SyncTrigger, date: Date) {}
    func lastSync(romId: Int) -> SyncMetadata? {
        lastSyncByRomId[romId].map { SyncMetadata(date: $0, trigger: .manual) }
    }
}
