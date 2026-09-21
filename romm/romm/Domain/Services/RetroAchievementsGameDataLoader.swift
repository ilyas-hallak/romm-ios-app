import Foundation

struct RetroAchievementsGameData: Equatable {
    let gameID: Int
    let achievements: [RetroAchievementsAchievementDefinition]
}

struct RetroAchievementsAchievementDefinition: Equatable {
    let id: Int
    let title: String
    let description: String?
    let points: Int
    let trigger: String
    let isCore: Bool
}

protocol PRetroAchievementsGameDataClient {
    func gameData(
        gameID: Int,
        credentials: RetroAchievementsCredentials
    ) async throws -> RetroAchievementsGameData?
}

/// Fetches a matched game's definitions and makes its core achievements active.
final class RetroAchievementsGameDataLoader {
    private let credentialsStore: PRetroAchievementsCredentialsStore
    private let client: PRetroAchievementsGameDataClient

    init(
        credentialsStore: PRetroAchievementsCredentialsStore,
        client: PRetroAchievementsGameDataClient
    ) {
        self.credentialsStore = credentialsStore
        self.client = client
    }

    func load(gameID: Int, into evaluator: RetroAchievementsEvaluator) async -> RetroAchievementsRuntimeState {
        guard gameID > 0, let credentials = credentialsStore.credentials() else {
            return .inactive
        }

        do {
            guard let gameData = try await client.gameData(gameID: gameID, credentials: credentials) else {
                return .unsupportedGame
            }

            for achievement in gameData.achievements where achievement.isCore {
                _ = evaluator.activate(achievementID: achievement.id, definition: achievement.trigger)
            }
            return .active(gameId: gameData.gameID)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
