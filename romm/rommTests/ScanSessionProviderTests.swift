//
//  ScanSessionProviderTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

// MARK: - Stubs

private final class LoginAPIClient: StubRommAPIClient {
    /// One entry per call, so a test can say what the second attempt does.
    var attempts: [(username: String, password: String)] = []
    var results: [Result<RommSessionCookie, Error>]

    init(results: [Result<RommSessionCookie, Error>]) {
        self.results = results
    }

    override func login(username: String, password: String) async throws -> RommSessionCookie {
        attempts.append((username, password))
        guard !results.isEmpty else { fatalError("login called more often than the test expected") }
        return try results.removeFirst().get()
    }
}

private final class StubTokenProvider: PTokenProvider {
    var username: String?
    var password: String?

    func getAuthToken() -> String? { nil }
    func getServerURL() -> String? { "https://server" }
    func getUsername() -> String? { username }
    func getPassword() -> String? { password }
    func isConfigured() -> Bool { true }
    func getAuthMethod() -> AuthMethod { username == nil ? .clientToken : .classic }
    func getClientToken() -> String? { nil }
    func getClientTokenInfo() -> ClientTokenInfo? { nil }
    func hasScope(_ scope: String) -> Bool { true }
    var availableScopes: [String]? { nil }
}

private final class InMemoryKeychain: PKeychainService {
    var values: [String: String] = [:]
    var saveError: Error?

    func save(key: String, value: String) throws {
        if let saveError { throw saveError }
        values[key] = value
    }

    func get(key: String) -> String? { values[key] }

    func delete(key: String) throws { values.removeValue(forKey: key) }
}

private final class StubCredentialsPrompt: PScanCredentialsPrompt, @unchecked Sendable {
    /// What the user types, one entry per time the sheet comes up. An empty
    /// list means they dismissed it.
    var answers: [ScanCredentials]
    private(set) var retryReasons: [String?] = []

    init(answers: [ScanCredentials] = []) {
        self.answers = answers
    }

    var askCount: Int { retryReasons.count }

    func credentials(retryReason: String?) async -> ScanCredentials? {
        retryReasons.append(retryReason)
        return answers.isEmpty ? nil : answers.removeFirst()
    }
}

private func cookie(_ value: String = "romm_session=abc", expiresAt: Date? = nil) -> RommSessionCookie {
    RommSessionCookie(headerValue: value, expiresAt: expiresAt)
}

// MARK: - Tests

@MainActor
struct ScanSessionProviderTests {

    private func makeProvider(
        api: LoginAPIClient,
        token: StubTokenProvider = StubTokenProvider(),
        prompt: StubCredentialsPrompt = StubCredentialsPrompt(),
        keychain: InMemoryKeychain = InMemoryKeychain()
    ) -> ScanSessionProvider {
        ScanSessionProvider(
            apiClient: api,
            tokenProvider: token,
            credentialsPrompt: prompt,
            keychainService: keychain
        )
    }

    @Test func signsInWithThePasswordAClassicLoginAlreadyHas() async throws {
        let api = LoginAPIClient(results: [.success(cookie())])
        let token = StubTokenProvider()
        token.username = "ilyas"
        token.password = "hunter2"
        let prompt = StubCredentialsPrompt()

        let provider = makeProvider(api: api, token: token, prompt: prompt)
        let header = try await provider.sessionCookie()

        #expect(header == "romm_session=abc")
        #expect(prompt.askCount == 0)
        #expect(api.attempts.first?.username == "ilyas")
    }

    @Test func asksTheUserWhenTheAppHasNoPasswordOnHand() async throws {
        // A device flow or client token sign-in carries no password.
        let api = LoginAPIClient(results: [.success(cookie())])
        let prompt = StubCredentialsPrompt(answers: [ScanCredentials(username: "ilyas", password: "typed")])
        let keychain = InMemoryKeychain()

        let provider = makeProvider(api: api, prompt: prompt, keychain: keychain)
        _ = try await provider.sessionCookie()

        #expect(prompt.retryReasons == [nil])
        #expect(api.attempts.first?.password == "typed")
        // Typed once, kept for the next scan.
        #expect(keychain.values[ScanSessionProvider.usernameKeychainKey] == "ilyas")
        #expect(keychain.values[ScanSessionProvider.passwordKeychainKey] == "typed")
    }

    @Test func reusesWhatWasTypedIntoAnEarlierPrompt() async throws {
        let api = LoginAPIClient(results: [.success(cookie())])
        let prompt = StubCredentialsPrompt()
        let keychain = InMemoryKeychain()
        keychain.values[ScanSessionProvider.usernameKeychainKey] = "ilyas"
        keychain.values[ScanSessionProvider.passwordKeychainKey] = "stored"

        let provider = makeProvider(api: api, prompt: prompt, keychain: keychain)
        _ = try await provider.sessionCookie()

        #expect(prompt.askCount == 0)
        #expect(api.attempts.first?.password == "stored")
    }

    @Test func doesNotSignInTwiceForTheSameSession() async throws {
        let api = LoginAPIClient(results: [.success(cookie())])
        let prompt = StubCredentialsPrompt(answers: [ScanCredentials(username: "ilyas", password: "typed")])

        let provider = makeProvider(api: api, prompt: prompt)
        _ = try await provider.sessionCookie()
        let second = try await provider.sessionCookie()

        #expect(second == "romm_session=abc")
        #expect(api.attempts.count == 1)
    }

    @Test func signsInAgainAfterTheServerRefusedTheSession() async throws {
        let api = LoginAPIClient(results: [.success(cookie()), .success(cookie("romm_session=def"))])
        let prompt = StubCredentialsPrompt(answers: [
            ScanCredentials(username: "ilyas", password: "typed"),
            ScanCredentials(username: "ilyas", password: "typed")
        ])

        let provider = makeProvider(api: api, prompt: prompt)
        _ = try await provider.sessionCookie()
        provider.invalidate()
        let second = try await provider.sessionCookie()

        #expect(second == "romm_session=def")
        #expect(api.attempts.count == 2)
    }

    @Test func aCookieThatIsAboutToExpireIsNotReused() async throws {
        let api = LoginAPIClient(results: [
            .success(cookie("romm_session=old", expiresAt: Date().addingTimeInterval(30))),
            .success(cookie("romm_session=new"))
        ])
        let prompt = StubCredentialsPrompt(answers: [
            ScanCredentials(username: "ilyas", password: "typed"),
            ScanCredentials(username: "ilyas", password: "typed")
        ])

        let provider = makeProvider(api: api, prompt: prompt)
        _ = try await provider.sessionCookie()

        #expect(try await provider.sessionCookie() == "romm_session=new")
    }

    @Test func aRejectedPasswordLeadsStraightBackToThePrompt() async throws {
        let api = LoginAPIClient(results: [
            .failure(APIClientError.authenticationRequired),
            .success(cookie())
        ])
        let token = StubTokenProvider()
        token.username = "ilyas"
        token.password = "outdated"
        let prompt = StubCredentialsPrompt(answers: [ScanCredentials(username: "ilyas", password: "correct")])

        let provider = makeProvider(api: api, token: token, prompt: prompt)
        let header = try await provider.sessionCookie()

        #expect(header == "romm_session=abc")
        #expect(api.attempts.map(\.password) == ["outdated", "correct"])
        // The sheet comes back saying why, rather than the scan just failing.
        #expect(prompt.retryReasons == ["The server did not accept these credentials."])
    }

    @Test func dropsStoredCredentialsTheServerRefused() async throws {
        let api = LoginAPIClient(results: [
            .failure(APIClientError.authenticationRequired),
            .success(cookie())
        ])
        let keychain = InMemoryKeychain()
        keychain.values[ScanSessionProvider.usernameKeychainKey] = "ilyas"
        keychain.values[ScanSessionProvider.passwordKeychainKey] = "outdated"
        let prompt = StubCredentialsPrompt(answers: [ScanCredentials(username: "ilyas", password: "correct")])

        let provider = makeProvider(api: api, prompt: prompt, keychain: keychain)
        _ = try await provider.sessionCookie()

        // Retrying the same refused password forever would be the alternative.
        #expect(keychain.values[ScanSessionProvider.passwordKeychainKey] == "correct")
    }

    @Test func aDismissedPromptCancelsTheScanRatherThanFailingIt() async {
        let api = LoginAPIClient(results: [])
        let prompt = StubCredentialsPrompt(answers: [])

        let provider = makeProvider(api: api, prompt: prompt)

        await #expect(throws: CancellationError.self) {
            _ = try await provider.sessionCookie()
        }
        #expect(api.attempts.isEmpty)
    }

    @Test func aKeychainThatRefusesToStoreDoesNotStopTheScan() async throws {
        let api = LoginAPIClient(results: [.success(cookie())])
        let keychain = InMemoryKeychain()
        keychain.saveError = KeychainError.saveFailed(-25299)
        let prompt = StubCredentialsPrompt(answers: [ScanCredentials(username: "ilyas", password: "typed")])

        let provider = makeProvider(api: api, prompt: prompt, keychain: keychain)

        #expect(try await provider.sessionCookie() == "romm_session=abc")
    }

    @Test func failuresOtherThanARefusedPasswordReachTheCaller() async {
        let api = LoginAPIClient(results: [.failure(APIClientError.invalidResponse(500, "boom"))])
        let token = StubTokenProvider()
        token.username = "ilyas"
        token.password = "hunter2"

        let provider = makeProvider(api: api, token: token)

        await #expect(throws: APIClientError.self) {
            _ = try await provider.sessionCookie()
        }
    }
}
