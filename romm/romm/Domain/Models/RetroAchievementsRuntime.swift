import Foundation

/// Credentials issued by RetroAchievements for live achievement evaluation.
struct RetroAchievementsCredentials: Equatable {
    let username: String
    let apiKey: String
}

/// An achievement unlocked by the runtime during an emulator session.
struct RetroAchievementsUnlock: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String?
    let points: Int
    let unlockedAt: Date
    let isHardcore: Bool
}

/// A live session's externally visible state.
enum RetroAchievementsRuntimeState: Equatable {
    case inactive
    case identifyingGame
    case active(gameId: Int)
    case unsupportedGame
    case failed(message: String)
}

/// Supplies a stable copy of emulated memory to an achievement runtime.
protocol PAchievementMemoryProvider {
    func readMemory(address: UInt32, length: Int) -> Data?
}
