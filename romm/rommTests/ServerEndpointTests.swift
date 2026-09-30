//
//  ServerEndpointTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

private let primaryURL = "http://192.168.1.10:8080"
private let alternativeURL = "https://romm.example.com"

private final class InMemorySetupRepository: PSetupRepository {
    var config: SetupConfiguration?

    init(alternativeServerURL: String? = nil) {
        config = SetupConfiguration(
            serverURL: primaryURL,
            username: "user",
            password: nil,
            token: "token",
            refreshToken: nil,
            setupDate: Date(),
            version: "5.3.0",
            alternativeServerURL: alternativeServerURL
        )
    }

    func saveSetupConfiguration(_ config: SetupConfiguration) throws { self.config = config }
    func getSetupConfiguration() -> SetupConfiguration? { config }
    func isSetupComplete() -> Bool { config != nil }
    func clearSetupConfiguration() throws { config = nil }
    func updateToken(_ token: String) throws {}
    func updateAlternativeServerURL(_ url: String?) throws { config?.alternativeServerURL = url }
    func saveAndValidateConfiguration(
        serverURL: String,
        username: String,
        password: String,
        allowIncompatibleVersionLogin: Bool
    ) async throws -> SetupConfiguration {
        fatalError("Not used")
    }
    func getAuthMethod() -> AuthMethod { .classic }
    func saveAuthMethod(_ method: AuthMethod) throws {}
    func saveClientTokenSetup(serverURL: String, tokenName: String, version: String, allowIncompatibleVersionLogin: Bool) throws {}
    func clearClientTokenData() throws {}
}

private final class StubEndpointRepository: PServerEndpointRepository {
    var activeEndpoint: ServerEndpoint
    var reachableURLs: Set<String>
    private(set) var probedURLs: [String] = []

    init(active: ServerEndpoint = .primary, reachable: Set<String> = []) {
        activeEndpoint = active
        reachableURLs = reachable
    }

    func setActiveEndpoint(_ endpoint: ServerEndpoint) { activeEndpoint = endpoint }

    func isReachable(_ serverURL: String) async -> Bool {
        probedURLs.append(serverURL)
        return reachableURLs.contains(serverURL)
    }
}

@MainActor
struct ResolveServerEndpointUseCaseTests {

    @Test func keepsPrimaryWhenItAnswers() async {
        let endpoints = StubEndpointRepository(active: .alternative, reachable: [primaryURL, alternativeURL])
        let useCase = ResolveServerEndpointUseCase(
            setupRepository: InMemorySetupRepository(alternativeServerURL: alternativeURL),
            endpointRepository: endpoints
        )

        #expect(await useCase.execute() == .primary)
        #expect(endpoints.activeEndpoint == .primary)
        #expect(endpoints.probedURLs == [primaryURL])
    }

    @Test func switchesToAlternativeWhenPrimaryIsUnreachable() async {
        let endpoints = StubEndpointRepository(reachable: [alternativeURL])
        let useCase = ResolveServerEndpointUseCase(
            setupRepository: InMemorySetupRepository(alternativeServerURL: alternativeURL),
            endpointRepository: endpoints
        )

        #expect(await useCase.execute() == .alternative)
        #expect(endpoints.activeEndpoint == .alternative)
    }

    @Test func keepsTheCurrentChoiceWhenNeitherAnswers() async {
        let endpoints = StubEndpointRepository(active: .alternative)
        let useCase = ResolveServerEndpointUseCase(
            setupRepository: InMemorySetupRepository(alternativeServerURL: alternativeURL),
            endpointRepository: endpoints
        )

        #expect(await useCase.execute() == .alternative)
        #expect(endpoints.activeEndpoint == .alternative)
    }

    @Test func usesPrimaryWithoutProbingWhenNoAlternativeIsSaved() async {
        let endpoints = StubEndpointRepository(active: .alternative)
        let useCase = ResolveServerEndpointUseCase(
            setupRepository: InMemorySetupRepository(),
            endpointRepository: endpoints
        )

        #expect(await useCase.execute() == .primary)
        #expect(endpoints.activeEndpoint == .primary)
        #expect(endpoints.probedURLs.isEmpty)
    }
}

@MainActor
struct SaveAlternativeServerURLUseCaseTests {

    @Test func storesTrimmedURL() throws {
        let setup = InMemorySetupRepository()
        try SaveAlternativeServerURLUseCase(setupRepository: setup).execute("  https://romm.example.com/ \n")
        #expect(setup.config?.alternativeServerURL == alternativeURL)
    }

    @Test func emptyInputRemovesTheURL() throws {
        let setup = InMemorySetupRepository(alternativeServerURL: alternativeURL)
        try SaveAlternativeServerURLUseCase(setupRepository: setup).execute("   ")
        #expect(setup.config?.alternativeServerURL == nil)
    }

    @Test(arguments: ["romm.example.com", "ftp://romm.example.com", "https://"])
    func rejectsURLsWithoutHTTPSchemeOrHost(input: String) {
        let setup = InMemorySetupRepository(alternativeServerURL: alternativeURL)
        #expect(throws: SetupUseCaseError.self) {
            try SaveAlternativeServerURLUseCase(setupRepository: setup).execute(input)
        }
        #expect(setup.config?.alternativeServerURL == alternativeURL)
    }
}

@MainActor
struct TokenProviderServerURLTests {

    @Test func returnsAlternativeWhileItIsActive() {
        let provider = TokenProvider(
            setupRepository: InMemorySetupRepository(alternativeServerURL: alternativeURL),
            endpointRepository: StubEndpointRepository(active: .alternative)
        )
        #expect(provider.getServerURL() == alternativeURL)
    }

    @Test func fallsBackToPrimaryOnceTheAlternativeIsRemoved() {
        let provider = TokenProvider(
            setupRepository: InMemorySetupRepository(),
            endpointRepository: StubEndpointRepository(active: .alternative)
        )
        #expect(provider.getServerURL() == primaryURL)
    }
}

@MainActor
struct SetupConfigurationDecodingTests {

    @Test func configurationSavedBeforeTheAlternativeURLStillDecodes() throws {
        let json = """
        {"serverURL":"\(primaryURL)","username":"user","setupDate":0,"version":"5.3.0"}
        """
        let config = try JSONDecoder().decode(SetupConfiguration.self, from: Data(json.utf8))
        #expect(config.serverURL == primaryURL)
        #expect(config.alternativeServerURL == nil)
    }
}
