//
//  AppViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 08.08.25.
//

import Combine
import Foundation
import Observation
import os

enum AppState {
    case loading
    case setup
    case authenticated
    case authenticationFailed
}

/// Describes a server-version change detected while the user is logged in.
/// Presented as an alert so the user can choose to continue or log out,
/// instead of being logged out automatically.
struct ServerVersionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// The version reported by the server, persisted when the user chooses to continue.
    let newVersion: String?
}

@Observable
@MainActor
class AppViewModel {
    var appState: AppState = .loading

    /// Non-nil while a server-version change alert should be shown to the user.
    var serverVersionAlert: ServerVersionAlert?

    /// Single-flight guard: opening a game fires several requests at once, so an
    /// expired/revoked token produces a burst of parallel 401/403s. Without this,
    /// each one would re-run the logout, causing the reported sign-in loop (#59).
    private var isHandlingSessionExpiration = false

    private let logger = Logger.viewModel
    private let launchArguments = ProcessInfo.processInfo.arguments

    // Shared data for environment
    let appData = AppData()

    // Use Cases
    private let saveSetupConfigurationUseCase: PSaveSetupConfigurationUseCase
    private let getSetupConfigurationUseCase: PGetSetupConfigurationUseCase
    private let clearSetupConfigurationUseCase: PClearSetupConfigurationUseCase
    private let checkServerVersionUseCase: CheckServerVersionUseCase
    private let clearServerVersionUseCase: ClearServerVersionUseCase
    private let saveServerVersionUseCase: SaveServerVersionUseCase
    private let getHeartbeatUseCase: GetHeartbeatUseCase
    private let getCurrentUserUseCase: GetCurrentUserUseCase

    private let factory: PDependencyFactory

    private var cancellables = Set<AnyCancellable>()
    private var isUITesting: Bool { launchArguments.contains("-ui_testing") || launchArguments.contains("-FASTLANE_SNAPSHOT") }
    private var shouldForceSetupForUITests: Bool { launchArguments.contains("-ui_testing_force_setup") }
    private var shouldForceAuthenticatedForUITests: Bool { launchArguments.contains("-ui_testing_force_authenticated") }

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.factory = factory
        self.saveSetupConfigurationUseCase = factory.makeSaveSetupConfigurationUseCase()
        self.getSetupConfigurationUseCase = factory.makeGetSetupConfigurationUseCase()
        self.clearSetupConfigurationUseCase = factory.makeClearSetupConfigurationUseCase()
        self.checkServerVersionUseCase = factory.makeCheckServerVersionUseCase()
        self.clearServerVersionUseCase = factory.makeClearServerVersionUseCase()
        self.saveServerVersionUseCase = factory.makeSaveServerVersionUseCase()
        self.getHeartbeatUseCase = factory.makeGetHeartbeatUseCase()
        self.getCurrentUserUseCase = factory.makeGetCurrentUserUseCase()

        // Listen for restart setup requests
        NotificationCenter.default.addObserver(
            forName: .restartSetupRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRestartSetupRequest()
            }
        }

        // Listen for session expiration (401 errors during usage)
        NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSessionExpiration()
            }
        }
    }

    // MARK: - Public Methods

    func checkInitialState() async {
        logger.debug("Checking initial state...")
        // A fresh auth attempt is underway — allow session-expiry handling again.
        isHandlingSessionExpiration = false

        if shouldForceSetupForUITests {
            resetAuthenticationState()
            appData.updateConfiguration(nil)
            appState = .setup
            return
        }

        if shouldForceAuthenticatedForUITests {
            seedUITestAuthenticatedState()
            appState = .authenticated
            return
        }

        let config = try? getSetupConfigurationUseCase.execute()

        if let config {
            // Check if we have valid auth: either a token in config (classic)
            // or a client token in Keychain
            let authMethod = SetupRepository().getAuthMethod()
            let hasAuth = config.token != nil || (authMethod == .clientToken && ClientTokenAuthService().getToken() != nil)

            if hasAuth {
                logger.info("Authentication state: \(appData.isAuthenticated) (method: \(authMethod.displayName))")
                updateAppConfig(config)
                appState = .authenticated
                await loadCurrentUser()
                // Verify the server version right after launch, not only on foreground.
                await checkServerVersionOnForeground()
            } else {
                logger.info("Setup not complete, showing setup")
                appState = .setup
            }
        } else {
            logger.info("No configuration found, showing setup")
            appState = .setup
        }
    }

    // MARK: - Setup Methods

    func saveConfiguration(serverURL: String, username: String, password: String) async {
        logger.debug("Save configuration requested")
        appState = .loading
        guard !serverURL.isEmpty, !username.isEmpty, !password.isEmpty else {
            logger.warning("Missing required fields")
            appData.updateError("Please fill in all required fields")
            return
        }

        appData.updateLoading(true)
        appData.updateError(nil)

        do {
            logger.debug("Calling save setup configuration use case...")
            let setupConfig = try await saveSetupConfigurationUseCase.execute(
                serverURL: serverURL,
                username: username,
                password: password,
                allowIncompatibleVersionLogin: true
            )

            try SetupRepository().saveAuthMethod(.classic)
            updateAppConfig(setupConfig)
            logger.info("Setup configuration saved successfully")
            appData.updateLoading(false)
            isHandlingSessionExpiration = false
            appState = .authenticated
            await loadCurrentUser()
        } catch {
            logger.error("Setup configuration failed: \(error)")
            appData.updateLoading(false)
            appData.updateError(error.localizedDescription)
            appState = .setup
        }
    }

    func restartSetup() {
        logger.debug("Restarting setup...")

        do {
            try clearSetupConfigurationUseCase.execute()
            resetAuthenticationState()
            clearServerVersionUseCase.execute()
            acknowledgedServerVersion = nil
            appData.updateConfiguration(nil)
            appState = .loading
        } catch {
            logger.error("Failed to restart setup: \(error)")
            appData.updateError(error.localizedDescription)
        }
    }

    private func updateAppConfig(_ config: SetupConfiguration) {
        appData.updateConfiguration(
            .init(
                serverURL: config.serverURL, username: config.username, password: "",
                token: config.token, refreshToken: config.refreshToken))
    }

    private func resetAuthenticationState() {
        logger.debug("Resetting authentication state")
        appData.updateAuthState(false)
        appData.updateUser(nil)
        appData.updateError(nil)
    }

    /// Keeps app-wide user data, including RetroAchievements progress, current.
    private func loadCurrentUser() async {
        do {
            appData.updateUser(try await getCurrentUserUseCase.execute())
        } catch {
            logger.warning("Unable to load current user: \(error.localizedDescription)")
        }
    }

    func clearError() {
        appData.updateError(nil)
    }

    // MARK: - Private Methods

    private func handleRestartSetupRequest() {
        logger.info("Handling restart setup request from notification")
        resetAuthenticationState()
        clearServerVersionUseCase.execute()
        appData.updateConfiguration(nil)
        appState = .setup
    }

    private func handleSessionExpiration() {
        logger.warning("Session expired - 401 error detected during usage")

        // Only handle session expiration if user was authenticated (not during setup)
        guard appState == .authenticated else {
            logger.debug("Ignoring session expiration - not in authenticated state")
            return
        }

        // Collapse a burst of parallel 401/403s into a single logout (#59).
        guard !isHandlingSessionExpiration else {
            logger.debug("Ignoring session expiration - already handling one")
            return
        }
        isHandlingSessionExpiration = true

        // Clear configuration and redirect to setup
        do {
            try clearSetupConfigurationUseCase.execute()
            resetAuthenticationState()
            clearServerVersionUseCase.execute()
            acknowledgedServerVersion = nil
            appData.updateConfiguration(nil)
            appData.updateError("Your session has expired. Please login again.")
            appState = .setup
            logger.info("User logged out due to session expiration")
        } catch {
            logger.error("Failed to clear configuration on session expiration: \(error)")
            appData.updateError("Session expired - please restart the app")
        }
    }

    // MARK: - Server Version Check

    /// Check server version on app foreground. Handles errors and logs out if needed.
    func checkServerVersionOnForeground() async {
        if isUITesting {
            logger.debug("Skipping version check in UI testing mode")
            return
        }

        // Only check if authenticated
        guard appState == .authenticated else {
            logger.debug("Skipping version check - not authenticated")
            return
        }

        // Check throttle via use case
        if checkServerVersionUseCase.shouldThrottle() {
            logger.debug("Skipping version check - throttled")
            return
        }

        logger.info("Checking server version on foreground...")

        do {
            // Always check the real compatibility. Whether we warn is decided in
            // handleHeartbeatError based on what the user already acknowledged.
            _ = try await checkServerVersionUseCase.execute(allowIncompatibleVersion: false)
            logger.info("Server version check passed")
        } catch let error as HeartbeatError {
            handleHeartbeatError(error)
        } catch {
            // Network errors should not trigger anything
            logger.warning("Version check failed (network error): \(error.localizedDescription)")
        }
    }

    /// Handle a HeartbeatError. Version-related issues no longer log the user
    /// out automatically — instead an alert is presented so the user can decide.
    /// A version the user already acknowledged is not re-reported.
    private func handleHeartbeatError(_ error: HeartbeatError) {
        logger.warning("Heartbeat error: \(error.localizedDescription)")

        let affectedVersion: String?
        let alertTitle: String
        switch error {
        case .serverVersionChanged(_, let to):
            affectedVersion = to
            alertTitle = "Server Version Changed"
        case .serverVersionTooHigh(let serverVersion, _):
            affectedVersion = serverVersion
            alertTitle = "Unsupported Server Version"
        case .serverVersionTooLow(let serverVersion, _):
            affectedVersion = serverVersion
            alertTitle = "Unsupported Server Version"
        case .decodingError, .networkError:
            // Transient errors should not disturb the user or log them out.
            logger.warning("Ignoring transient heartbeat error: \(error.localizedDescription)")
            return
        }

        // Don't keep nagging about a version the user already accepted.
        if let affectedVersion, affectedVersion == acknowledgedServerVersion {
            logger.info("Server version \(affectedVersion) already acknowledged - not alerting")
            return
        }

        presentServerVersionAlert(title: alertTitle, message: error.errorDescription, newVersion: affectedVersion)
    }

    private func presentServerVersionAlert(title: String, message: String?, newVersion: String?) {
        guard appState == .authenticated, serverVersionAlert == nil else { return }
        serverVersionAlert = ServerVersionAlert(
            title: title,
            message: message ?? "The server version has changed. Some features may not work correctly.",
            newVersion: newVersion
        )
    }

    /// User chose to keep using the app despite the server-version change.
    func continueWithServerVersionChange() {
        if let newVersion = serverVersionAlert?.newVersion {
            // Remember this exact version so we don't warn about it again,
            // and treat it as the last known version going forward.
            acknowledgedServerVersion = newVersion
            saveServerVersion(newVersion)
        }
        serverVersionAlert = nil
    }

    /// User chose to log out in response to the server-version change.
    func logoutFromServerVersionAlert() {
        let message = serverVersionAlert?.message
        serverVersionAlert = nil
        performVersionLogout(message: message)
    }

    private func performVersionLogout(message: String?) {
        do {
            try clearSetupConfigurationUseCase.execute()
            resetAuthenticationState()
            clearServerVersionUseCase.execute()
            acknowledgedServerVersion = nil
            appData.updateConfiguration(nil)
            if let message {
                appData.updateError(message)
            }
            appState = .setup
            logger.info("User logged out due to server-version change")
        } catch {
            logger.error("Failed to log out after server-version change: \(error)")
            appData.updateError("Error - please restart the app")
        }
    }

    // MARK: - Acknowledged Server Version

    private let acknowledgedServerVersionKey = "heartbeat.acknowledgedServerVersion"

    /// The server version the user explicitly accepted despite it being outside
    /// the supported range. Persisted so we don't warn about the same version twice.
    private var acknowledgedServerVersion: String? {
        get { UserDefaults.standard.string(forKey: acknowledgedServerVersionKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: acknowledgedServerVersionKey)
            } else {
                UserDefaults.standard.removeObject(forKey: acknowledgedServerVersionKey)
            }
        }
    }

    /// Remember that the user accepted this (incompatible) version during setup.
    func acknowledgeServerVersion(_ version: String) {
        acknowledgedServerVersion = version
    }

    // MARK: - Version Check Helpers (for SetupView)

    /// Check if a server version is compatible
    func isVersionCompatible(_ serverVersion: String) -> Bool {
        checkServerVersionUseCase.isVersionCompatible(serverVersion)
    }

    /// Get minimum supported server version
    var minSupportedServerVersion: String {
        checkServerVersionUseCase.minSupportedServerVersion
    }

    /// Get maximum supported server version
    var maxSupportedServerVersion: String {
        checkServerVersionUseCase.maxSupportedServerVersion
    }

    /// Save server version after successful login
    func saveServerVersion(_ version: String) {
        saveServerVersionUseCase.execute(version: version)
    }

    /// Fetch server version from a specific URL (for setup flow before login)
    func fetchServerVersion(from serverURL: String) async throws -> String {
        let heartbeat = try await getHeartbeatUseCase.execute(from: serverURL)
        return heartbeat.version
    }

    private func seedUITestAuthenticatedState() {
        appData.updateAuthState(true)
        appData.updateError(nil)
        appData.updateConfiguration(
            AppConfiguration(
                serverURL: "https://demo.romm.app",
                username: "snapshot-user",
                password: nil,
                token: "snapshot-token",
                refreshToken: nil
            )
        )
        appData.updateUser(
            User(
                id: 1,
                username: "snapshot-user",
                email: "snapshot@example.com",
                role: .admin,
                avatarPath: nil,
                enabled: true
            )
        )
    }
}
