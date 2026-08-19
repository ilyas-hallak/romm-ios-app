import Testing
import Foundation
@testable import romm

private final class StubPreference: PEmulatorEnginePreference {
    var current: EmulatorEngine
    init(_ engine: EmulatorEngine) { self.current = engine }
}

private final class StubSupport: PPlatformEngineSupport {
    var engines: Set<EmulatorEngine> = []
    func supportedEngines(for platformSlug: String) -> Set<EmulatorEngine> { engines }
    func preferred(for platformSlug: String) -> EmulatorEngine {
        engines.contains(.web) ? .web : .native
    }
    func isEmulationAvailable(for platformSlug: String) -> Bool { !engines.isEmpty }
}

private final class StubTokenProvider: PTokenProvider {
    var serverURL: String? = "https://server"
    func getAuthToken() -> String? { nil }
    func getServerURL() -> String? { serverURL }
    func getUsername() -> String? { nil }
    func getPassword() -> String? { nil }
    func isConfigured() -> Bool { serverURL != nil }
    func getAuthMethod() -> AuthMethod { .classic }
    func getClientToken() -> String? { nil }
    func getClientTokenInfo() -> ClientTokenInfo? { nil }
    func hasScope(_ scope: String) -> Bool { false }
    var availableScopes: [String]? { nil }
}

private final class StubCheckSupport: PCheckEmulatorSupportUseCase {
    var supported = true
    func execute(platformSlug: String) -> Bool { supported }
}

private func makeRom(slug: String = "gba") -> Rom {
    Rom(id: 1, name: "Test", platformId: 0, urlCover: nil,
        isFavourite: false, hasRetroAchievements: false, isPlayable: true,
        fileName: "Test.gba", platformSlug: slug)
}

struct LaunchEmulatorUseCaseTests {
    @Test func failsWhenNoServer() async {
        let token = StubTokenProvider(); token.serverURL = nil
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: token,
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.web),
            platformSupport: StubSupport()
        )
        let result = await useCase.execute(rom: makeRom())
        if case .failure(.noServerConfigured) = result {} else { Issue.record("expected .noServerConfigured") }
    }

    @Test func webPreferenceReturnsWebDecision() async {
        let support = StubSupport(); support.engines = [.web]
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: StubTokenProvider(),
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.web),
            platformSupport: support
        )
        let result = await useCase.execute(rom: makeRom())
        if case .success(let decision) = result, case .web = decision {} else {
            Issue.record("expected .web decision")
        }
    }

    @Test func deltaPreferenceReturnsDeltaDecisionForGBA() async {
        let support = StubSupport(); support.engines = [.web, .native]
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: StubTokenProvider(),
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.native),
            platformSupport: support
        )
        let result = await useCase.execute(rom: makeRom(slug: "gba"))
        if case .success(let decision) = result,
           case .native(_, let gameType) = decision {
            #expect(gameType == .gba)
        } else {
            Issue.record("expected .native(.gba) decision")
        }
    }

    @Test func deltaPreferenceFallsBackToWebWhenUnsupported() async {
        let support = StubSupport(); support.engines = [.web]
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: StubTokenProvider(),
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.native),
            platformSupport: support
        )
        let result = await useCase.execute(rom: makeRom(slug: "psx"))
        if case .success(let decision) = result, case .web = decision {} else {
            Issue.record("expected fallback to .web")
        }
    }
}
