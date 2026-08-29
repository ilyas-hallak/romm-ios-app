import Observation

@Observable
final class RetroAchievementsCredentialsViewModel {
    var username: String
    var apiKey: String
    private(set) var errorMessage: String?

    private let store: PRetroAchievementsCredentialsStore

    init(store: PRetroAchievementsCredentialsStore = RetroAchievementsCredentialsStore()) {
        self.store = store
        let credentials = store.credentials()
        username = credentials?.username ?? ""
        apiKey = credentials?.apiKey ?? ""
    }

    var isConfigured: Bool {
        store.credentials() != nil
    }

    @discardableResult
    func save() -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedAPIKey.isEmpty else {
            errorMessage = "Enter both a username and API key."
            return false
        }

        do {
            try store.save(.init(username: trimmedUsername, apiKey: trimmedAPIKey))
            username = trimmedUsername
            apiKey = trimmedAPIKey
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clear() {
        do {
            try store.clear()
            username = ""
            apiKey = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
