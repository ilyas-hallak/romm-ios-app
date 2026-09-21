import Foundation

protocol PRetroAchievementsCredentialsStore {
    func credentials() -> RetroAchievementsCredentials?
    func save(_ credentials: RetroAchievementsCredentials) throws
    func clear() throws
}

/// Stores live RetroAchievements credentials separately from RomM authentication.
final class RetroAchievementsCredentialsStore: PRetroAchievementsCredentialsStore {
    private enum Key {
        static let username = "retroachievements.username"
        static let apiKey = "retroachievements.apiKey"
    }

    private let keychain: PKeychainService

    init(keychain: PKeychainService = KeychainService.retroAchievements) {
        self.keychain = keychain
    }

    func credentials() -> RetroAchievementsCredentials? {
        guard let username = keychain.get(key: Key.username),
              let apiKey = keychain.get(key: Key.apiKey),
              !username.isEmpty,
              !apiKey.isEmpty else {
            return nil
        }
        return RetroAchievementsCredentials(username: username, apiKey: apiKey)
    }

    func save(_ credentials: RetroAchievementsCredentials) throws {
        try keychain.save(key: Key.username, value: credentials.username)
        try keychain.save(key: Key.apiKey, value: credentials.apiKey)
    }

    func clear() throws {
        try keychain.delete(key: Key.username)
        try keychain.delete(key: Key.apiKey)
    }
}

extension KeychainService {
    static let retroAchievements = KeychainService(service: "com.romm.retroachievements")
}
