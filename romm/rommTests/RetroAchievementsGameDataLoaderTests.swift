import Foundation
import Testing
@testable import romm

struct RetroAchievementsGameDataLoaderTests {
    @Test func loadsMatchedGameDefinitions() async throws {
        let credentials = TestCredentialsStore(credentials: .init(username: "player", apiKey: "secret"))
        let client = TestGameDataClient(result: .success(.init(gameID: 7, achievements: [
            .init(id: 42, title: "Core", description: nil, points: 5, trigger: "0xH0000=1", isCore: true),
            .init(id: 43, title: "Unofficial", description: nil, points: 5, trigger: "0xH0000=1", isCore: false)
        ])))
        let loader = RetroAchievementsGameDataLoader(credentialsStore: credentials, client: client)

        #expect(await loader.load(gameID: 7, into: RetroAchievementsEvaluator(memory: TestMemory(bytes: [0]))) == .active(gameId: 7))
        #expect(client.requestedGameID == 7)
    }

    @Test func remainsInactiveWithoutCredentials() async {
        let client = TestGameDataClient(result: .success(nil))
        let loader = RetroAchievementsGameDataLoader(credentialsStore: TestCredentialsStore(), client: client)

        #expect(await loader.load(gameID: 7, into: RetroAchievementsEvaluator(memory: TestMemory(bytes: [0]))) == .inactive)
        #expect(client.requestedGameID == nil)
    }

    @Test func reportsUnsupportedAndFailures() async {
        let credentials = TestCredentialsStore(credentials: .init(username: "player", apiKey: "secret"))
        let unsupported = RetroAchievementsGameDataLoader(credentialsStore: credentials, client: TestGameDataClient(result: .success(nil)))
        #expect(await unsupported.load(gameID: 7, into: RetroAchievementsEvaluator(memory: TestMemory(bytes: [0]))) == .unsupportedGame)

        let failed = RetroAchievementsGameDataLoader(credentialsStore: credentials, client: TestGameDataClient(result: .failure(TestError.offline)))
        #expect(await failed.load(gameID: 7, into: RetroAchievementsEvaluator(memory: TestMemory(bytes: [0]))) == .failed(message: "Offline"))
    }
}

private final class TestCredentialsStore: PRetroAchievementsCredentialsStore {
    private let value: RetroAchievementsCredentials?
    init(credentials: RetroAchievementsCredentials? = nil) { value = credentials }
    func credentials() -> RetroAchievementsCredentials? { value }
    func save(_ credentials: RetroAchievementsCredentials) throws {}
    func clear() throws {}
}

private final class TestGameDataClient: PRetroAchievementsGameDataClient {
    let result: Result<RetroAchievementsGameData?, Error>
    var requestedGameID: Int?
    init(result: Result<RetroAchievementsGameData?, Error>) { self.result = result }
    func gameData(gameID: Int, credentials: RetroAchievementsCredentials) async throws -> RetroAchievementsGameData? {
        requestedGameID = gameID
        return try result.get()
    }
}

private enum TestError: LocalizedError { case offline; var errorDescription: String? { "Offline" } }

private final class TestMemory: PAchievementMemoryProvider {
    var bytes: Data
    init(bytes: [UInt8]) { self.bytes = Data(bytes) }
    func readMemory(address: UInt32, length: Int) -> Data? {
        let offset = Int(address)
        guard offset >= 0, offset <= bytes.count, length <= bytes.count - offset else { return nil }
        return bytes.subdata(in: offset..<(offset + length))
    }
}
