import Testing
@testable import romm

struct RetroAchievementsCredentialsViewModelTests {
    @Test func loadsSavedCredentials() throws {
        let store = TestCredentialsStore()
        try store.save(.init(username: "player", apiKey: "secret"))

        let viewModel = RetroAchievementsCredentialsViewModel(store: store)

        #expect(viewModel.username == "player")
        #expect(viewModel.apiKey == "secret")
        #expect(viewModel.isConfigured)
    }

    @Test func rejectsBlankCredentials() {
        let viewModel = RetroAchievementsCredentialsViewModel(store: TestCredentialsStore())
        viewModel.username = " player "
        viewModel.apiKey = " \n"

        #expect(!viewModel.save())
        #expect(viewModel.errorMessage == "Enter both a username and API key.")
    }

    @Test func savesTrimmedCredentialsAndCanRemoveThem() {
        let store = TestCredentialsStore()
        let viewModel = RetroAchievementsCredentialsViewModel(store: store)
        viewModel.username = " player "
        viewModel.apiKey = " secret "

        #expect(viewModel.save())
        #expect(store.credentials() == .init(username: "player", apiKey: "secret"))

        viewModel.clear()
        #expect(!viewModel.isConfigured)
        #expect(viewModel.username.isEmpty)
        #expect(viewModel.apiKey.isEmpty)
    }
}

private final class TestCredentialsStore: PRetroAchievementsCredentialsStore {
    private var value: RetroAchievementsCredentials?

    func credentials() -> RetroAchievementsCredentials? { value }
    func save(_ credentials: RetroAchievementsCredentials) throws { value = credentials }
    func clear() throws { value = nil }
}
