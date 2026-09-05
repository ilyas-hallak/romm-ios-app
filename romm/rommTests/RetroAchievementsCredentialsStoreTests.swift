import Testing
@testable import romm

struct RetroAchievementsCredentialsStoreTests {
    @Test func savesReadsAndClearsCredentials() throws {
        let keychain = InMemoryKeychain()
        let store = RetroAchievementsCredentialsStore(keychain: keychain)
        let credentials = RetroAchievementsCredentials(username: "player", apiKey: "secret")

        try store.save(credentials)
        #expect(store.credentials() == credentials)

        try store.clear()
        #expect(store.credentials() == nil)
    }
}

private final class InMemoryKeychain: PKeychainService {
    private var values: [String: String] = [:]

    func save(key: String, value: String) throws {
        values[key] = value
    }

    func get(key: String) -> String? {
        values[key]
    }

    func delete(key: String) throws {
        values[key] = nil
    }
}
