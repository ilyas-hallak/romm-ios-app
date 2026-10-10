//
//  AppViewModelSessionExpirationTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

/// A 401 anywhere in the app posts `.sessionExpired` on the default center;
/// `AppViewModel` reacts by logging out and leaving a message in `AppData`
/// for `AppView` to show once at the root level (#218).
@MainActor
struct AppViewModelSessionExpirationTests {
    private let factory = SessionExpirationFactory()

    private func makeViewModel() -> AppViewModel {
        AppViewModel(factory: factory)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    @Test func leavesAMessageAndReturnsToSetup() async {
        let viewModel = makeViewModel()
        viewModel.appState = .authenticated

        NotificationCenter.default.post(name: .sessionExpired, object: nil)
        await waitUntil { viewModel.appState == .setup }

        #expect(viewModel.appData.errorMessage == "Your session has expired. Please login again.")
        #expect(factory.clearSetup.calls == 1)
    }

    @Test func clearsADanglingServerVersionAlertSoTheTwoNeverShowAtOnce() async {
        let viewModel = makeViewModel()
        viewModel.appState = .authenticated
        viewModel.serverVersionAlert = ServerVersionAlert(title: "Server Version Changed", message: "Update recommended.", newVersion: "5.4.0")

        NotificationCenter.default.post(name: .sessionExpired, object: nil)
        await waitUntil { viewModel.appState == .setup }

        #expect(viewModel.serverVersionAlert == nil)
        #expect(viewModel.appData.errorMessage == "Your session has expired. Please login again.")
    }

    @Test func isIgnoredWhileStillOnTheSetupScreen() async {
        let viewModel = makeViewModel()
        viewModel.appState = .setup

        NotificationCenter.default.post(name: .sessionExpired, object: nil)
        await waitUntil(timeout: 0.2) { viewModel.appData.errorMessage != nil }

        #expect(viewModel.appData.errorMessage == nil)
        #expect(factory.clearSetup.calls == 0)
    }
}

/// Swaps out everything a session-expiry logout touches, so no test reaches
/// the keychain, `DefaultConfigurationService.shared` or a real server.
private final class SessionExpirationFactory: MockDependencyFactory {
    let clearSetup = ClearSetupSpy()

    init() {
        super.init(
            authRepository: FakeAuthRepository(),
            setupRepository: StubSetupRepository(),
            heartbeatRepository: FakeHeartbeatRepository()
        )
    }

    override func makeClearSetupConfigurationUseCase() -> PClearSetupConfigurationUseCase { clearSetup }
}

private final class ClearSetupSpy: PClearSetupConfigurationUseCase {
    private(set) var calls = 0
    func execute() throws { calls += 1 }
}

/// Only here so `AppViewModel.init` can build its (unused in these tests)
/// setup-configuration use cases without tripping the factory's fatalError.
private final class StubSetupRepository: PSetupRepository {
    func saveSetupConfiguration(_ config: SetupConfiguration) throws {}
    func getSetupConfiguration() -> SetupConfiguration? { nil }
    func isSetupComplete() -> Bool { false }
    func clearSetupConfiguration() throws {}
    func updateToken(_ token: String) throws {}
    func updateAlternativeServerURL(_ url: String?) throws {}
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
