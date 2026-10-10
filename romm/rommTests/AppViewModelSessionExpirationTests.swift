//
//  AppViewModelSessionExpirationTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

/// A 401 anywhere in the app posts `.sessionExpired`; `AppViewModel` reacts by
/// logging out and leaving a message in `AppData` for `AppView` to show once
/// at the root level (#218). Uses a private `NotificationCenter` instead of
/// `.default`, so a concurrently running suite posting the same notification
/// can never reach (or be reached by) the view model under test.
@MainActor
struct AppViewModelSessionExpirationTests {
    private let factory = AppViewModelTestFactory()
    private let center = NotificationCenter()

    private func makeViewModel() -> AppViewModel {
        AppViewModel(factory: factory, notificationCenter: center)
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

        center.post(name: .sessionExpired, object: nil)
        await waitUntil { viewModel.appState == .setup }

        #expect(viewModel.appData.errorMessage == "Your session has expired. Please login again.")
        #expect(factory.clearSetup.calls == 1)
    }

    @Test func clearsADanglingServerVersionAlertSoTheTwoNeverShowAtOnce() async {
        let viewModel = makeViewModel()
        viewModel.appState = .authenticated
        viewModel.serverVersionAlert = ServerVersionAlert(title: "Server Version Changed", message: "Update recommended.", newVersion: "5.4.0")

        center.post(name: .sessionExpired, object: nil)
        await waitUntil { viewModel.appState == .setup }

        #expect(viewModel.serverVersionAlert == nil)
        #expect(viewModel.appData.errorMessage == "Your session has expired. Please login again.")
    }

    @Test func isIgnoredWhileStillOnTheSetupScreen() async {
        let viewModel = makeViewModel()
        viewModel.appState = .setup

        center.post(name: .sessionExpired, object: nil)
        await waitUntil(timeout: 0.2) { viewModel.appData.errorMessage != nil }

        #expect(viewModel.appData.errorMessage == nil)
        #expect(factory.clearSetup.calls == 0)
    }

    @Test func leavesADifferentMessageAndStaysAuthenticatedWhenClearingFails() async {
        let viewModel = makeViewModel()
        viewModel.appState = .authenticated
        factory.clearSetup.error = ClearSetupError()

        center.post(name: .sessionExpired, object: nil)
        await waitUntil { viewModel.appData.errorMessage != nil }

        #expect(viewModel.appState == .authenticated)
        #expect(viewModel.appData.errorMessage == "Session expired - please restart the app")
    }
}

@MainActor
struct AppViewModelSaveConfigurationTests {
    private let factory = AppViewModelTestFactory()
    private let center = NotificationCenter()

    private func makeViewModel() -> AppViewModel {
        AppViewModel(factory: factory, notificationCenter: center)
    }

    /// Regression test: a guard-fail used to leave `appState` on `.loading`
    /// forever (set just before the guard, never reset), so the error alert
    /// appeared over a spinner instead of back on the setup screen.
    @Test func leavesAppStateUnchangedWhenRequiredFieldsAreMissing() async {
        let viewModel = makeViewModel()
        viewModel.appState = .setup

        await viewModel.saveConfiguration(serverURL: "", username: "user", password: "pw")

        #expect(viewModel.appState == .setup)
        #expect(viewModel.appData.errorMessage == "Please fill in all required fields")
        #expect(factory.clearSetup.calls == 0)
    }
}

private struct ClearSetupError: Error {}

/// Swaps out everything a session-expiry logout touches, so no test reaches
/// the keychain, `DefaultConfigurationService.shared` or a real server.
private final class AppViewModelTestFactory: MockDependencyFactory {
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
    var error: Error?
    func execute() throws {
        calls += 1
        if let error { throw error }
    }
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
