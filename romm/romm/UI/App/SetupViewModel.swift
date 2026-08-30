//
//  SetupViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 07.08.25.
//

import Foundation
import SwiftUI
import UIKit

@Observable
@MainActor
final class SetupViewModel {
    // Dependencies — use cases only, no reference to the app root view model.
    private let saveSetupConfigurationUseCase: PSaveSetupConfigurationUseCase
    private let getHeartbeatUseCase: GetHeartbeatUseCase
    private let checkServerVersionUseCase: CheckServerVersionUseCase
    private let saveServerVersionUseCase: SaveServerVersionUseCase

    /// Called after a successful login so the app can re-evaluate auth state.
    /// The View wires this to `AppViewModel.checkInitialState()`.
    var onAuthenticated: () async -> Void = {}
    /// Called when the user accepts an incompatible server version during setup.
    /// The View wires this to `AppViewModel.acknowledgeServerVersion(_:)`.
    var onAcknowledgeVersion: (String) -> Void = { _ in }

    var serverURL = ""
    var username = ""
    var password = ""
    var showPassword = false
    var showConnectionDetails = false

    // Connection validation states
    var isConnecting = false
    var serverValidated = false
    var detectedServerVersion: String?
    var connectionError: String?
    var connectionErrorDetails: String?
    var isErrorExpanded = false
    var isVersionWarning = false
    var didAcceptIncompatibleVersion = false

    // Version warning detail text
    var versionWarningTitle: String?
    var versionWarningDetails: String?

    // Auth capability detection
    var detectedAuthCapability: HeartbeatRepository.AuthCapabilities?
    var selectedAuthMethod: AuthMethod = .classic

    // Client Token states
    var clientTokenInput = ""
    var isExchangingToken = false
    var clientTokenError: String?
    var showQRScanner = false

    // Device flow (browser) states
    var deviceFlowInit: DeviceAuthInitResponse?
    var isDeviceFlowRunning = false
    var deviceFlowError: String?
    var deviceFlowTask: Task<Void, Never>?

    // "Other sign-in options" disclosure
    var showOtherOptions = false

    // Classic login state (owned locally — no app-global state)
    var isLoggingIn = false
    var loginError: String?

    private var connectionLogger: ConnectionLogger { ConnectionLogger.shared }
    private let launchArguments = ProcessInfo.processInfo.arguments
    private var shouldShowLoginForUITests: Bool { launchArguments.contains("-ui_testing_show_login") }

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.saveSetupConfigurationUseCase = factory.makeSaveSetupConfigurationUseCase()
        self.getHeartbeatUseCase = factory.makeGetHeartbeatUseCase()
        self.checkServerVersionUseCase = factory.makeCheckServerVersionUseCase()
        self.saveServerVersionUseCase = factory.makeSaveServerVersionUseCase()
    }

    // MARK: - Computed helpers

    var isBusy: Bool {
        isLoggingIn || isExchangingToken || isConnecting || isDeviceFlowRunning
    }

    /// Whether the browser device-flow is the primary path. Optimistic before the
    /// server is validated; after validation, only when the server supports it.
    var showDeviceFlowPrimary: Bool {
        guard let cap = detectedAuthCapability else { return true }
        return cap.deviceFlow
    }

    /// Fallback methods (username/password, API token) shown under "Other options".
    var otherMethods: [AuthMethod] {
        guard let cap = detectedAuthCapability else { return [.classic, .clientToken] }
        return AuthMethod.availableMethods(for: cap).filter { $0 != .deviceFlow }
    }

    var canSubmit: Bool {
        guard !isBusy && !serverURL.isEmpty else { return false }
        switch selectedAuthMethod {
        case .deviceFlow:
            return false // Browser sign-in has its own button, not this one.
        case .classic:
            return !username.isEmpty && !password.isEmpty
        case .clientToken:
            return !clientTokenInput.isEmpty
        }
    }

    var hasLoginError: Bool {
        loginError != nil
    }

    var deviceFlowButtonEnabled: Bool {
        !serverURL.isEmpty && !isBusy
    }

    // MARK: - Primary Action Handler

    func handlePrimaryAction() async {
        if !serverValidated {
            await validateServer()
        }
        // Only proceed to login when server is validated, no hard error, and no unaccepted warning
        guard serverValidated && connectionError == nil else { return }
        // If version warning: accept incompatible version and remember it so the
        // foreground version check doesn't immediately warn about the same version.
        if isVersionWarning {
            didAcceptIncompatibleVersion = true
            if let version = detectedServerVersion {
                onAcknowledgeVersion(version)
            }
        }
        if selectedAuthMethod == .clientToken {
            await performClientTokenLogin()
        } else {
            await performClassicLogin()
        }
    }

    // MARK: - Actions

    func validateServer() async {
        hideKeyboard()
        isConnecting = true
        connectionError = nil
        connectionErrorDetails = nil
        isErrorExpanded = false
        isVersionWarning = false
        versionWarningTitle = nil
        versionWarningDetails = nil
        didAcceptIncompatibleVersion = false
        detectedAuthCapability = nil

        do {
            let version = try await getHeartbeatUseCase.execute(from: serverURL).version
            detectedServerVersion = version

            if checkServerVersionUseCase.isVersionCompatible(version) {
                serverValidated = true
                connectionError = nil
                didAcceptIncompatibleVersion = false
                await detectAuthenticationMethod()
            } else if version == "development" {
                versionWarningTitle = "Development Build"
                versionWarningDetails = "This server is running a development version of RomM. Compatibility is not guaranteed."
                isVersionWarning = true
                serverValidated = true
                await detectAuthenticationMethod()
            } else {
                versionWarningTitle = "Incompatible Server Version"
                versionWarningDetails = "Server v\(version) is outside the supported range (\(checkServerVersionUseCase.minSupportedServerVersion) – \(checkServerVersionUseCase.maxSupportedServerVersion)). Some features may not work correctly."
                isVersionWarning = true
                serverValidated = true
                await detectAuthenticationMethod()
            }
        } catch let error as APIClientError {
            if case .cloudflareProtection = error {
                connectionError = "Server is protected by Cloudflare"
                connectionErrorDetails = "This server is behind Cloudflare protection and cannot be accessed directly."
                isVersionWarning = false
            } else {
                let (message, details) = parseConnectionError(error)
                connectionError = message
                connectionErrorDetails = details
                isVersionWarning = false
            }
            serverValidated = false
            didAcceptIncompatibleVersion = false
        } catch let error as HeartbeatError {
            switch error {
            case .decodingError:
                connectionError = "Invalid Response"
                connectionErrorDetails = "The server did not return a valid RomM response. Is this a RomM server?"
            default:
                let (message, details) = parseConnectionError(error)
                connectionError = message
                connectionErrorDetails = details
            }
            isVersionWarning = false
            serverValidated = false
            didAcceptIncompatibleVersion = false
        } catch {
            let (message, details) = parseConnectionError(error)
            connectionError = message
            connectionErrorDetails = details
            isVersionWarning = false
            serverValidated = false
            didAcceptIncompatibleVersion = false
        }

        isConnecting = false
    }

    // MARK: - Auth Detection

    func detectAuthenticationMethod() async {
        let heartbeatRepo = HeartbeatRepository()
        Logger.auth.info("Detecting authentication methods...")
        let capabilities = await heartbeatRepo.detectAuthCapabilities(serverURL: serverURL)
        detectedAuthCapability = capabilities
        Logger.auth.info("Detected capabilities: \(capabilities.description)")
        connectionError = nil
        connectionErrorDetails = nil

        if capabilities.unreachable {
            serverValidated = false
            connectionError = "Server is unreachable"
            connectionErrorDetails = "Could not connect to the server."
            return
        }
        if capabilities.cloudflareBlocked {
            serverValidated = false
            connectionError = "Server is protected by Cloudflare"
            connectionErrorDetails = "This server is behind Cloudflare protection and cannot be accessed directly."
            return
        }
        serverValidated = true
        if capabilities.classic {
            selectedAuthMethod = .classic
        } else if capabilities.clientTokens {
            selectedAuthMethod = .clientToken
        }
    }

    func parseConnectionError(_ error: Error) -> (message: String, details: String?) {
        // The heartbeat wraps the API error, and unwrapping it is what makes the
        // specific cases below reachable at all. Without this everything falls
        // through to `localizedDescription`, which for an HTTP error is the
        // entire response body — users were shown raw HTML of a 404 page.
        if let heartbeatError = error as? HeartbeatError, case .networkError(let underlying) = heartbeatError {
            return parseConnectionError(underlying)
        }
        if let apiError = error as? APIClientError {
            switch apiError {
            case .cloudflareProtection:
                return ("Server is protected by Cloudflare", "This server is behind Cloudflare protection and cannot be accessed directly.")
            case .authenticationRequired:
                return ("Authentication failed", "Invalid username or password")
            case .invalidURL(let url):
                return ("Invalid URL", "The URL '\(url)' is not valid")
            case .noConfiguration:
                return ("Configuration error", "Server configuration is missing")
            case .noCredentials:
                return ("Credentials missing", "Please provide username and password")
            case .invalidResponse(let code, _):
                // Something answered, so the address and port are reachable, but
                // it does not serve RomM. Usually a different service on that
                // port, or a proxy that routes elsewhere.
                if code == 404 {
                    return ("No RomM server at this address",
                            "Something answered, but it is not RomM. Check the port and whether your reverse proxy points at RomM.")
                }
                return ("Server error (\(code))", "The server returned an error response")
            case .decodingError:
                return ("Invalid response", "The server did not return a valid RomM response")
            case .networkError(let underlyingError):
                return parseGeneralConnectionError(underlyingError)
            }
        }
        return parseGeneralConnectionError(error)
    }

    /// The failures a self-hosted setup actually produces, keyed by code so the
    /// phone's language cannot change the outcome.
    private func messageForURLError(_ code: URLError.Code) -> (message: String, details: String?)? {
        switch code {
        case .timedOut:
            return ("Connection timed out",
                    "The server did not answer in time. Check that the address and port are right and that the server is reachable from this network.")
        case .cannotConnectToHost, .networkConnectionLost:
            return ("Connection failed",
                    "Nothing is listening at that address. Check the port, and whether the server is running.")
        case .cannotFindHost, .dnsLookupFailed:
            return ("Server not found",
                    "The address could not be resolved. Check the spelling, and whether this network can see your server.")
        case .notConnectedToInternet:
            return ("No connection",
                    "This device is not connected to a network.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return ("Certificate problem",
                    "The secure connection could not be established. A self-signed certificate has to be trusted on this device, or use http:// instead.")
        case .unsupportedURL, .badURL:
            return ("Invalid address",
                    "Start the address with http:// or https://, for example http://192.168.1.50:8080.")
        case .appTransportSecurityRequiresSecureConnection:
            return ("Insecure connection blocked",
                    "iOS refused the plain http connection to this address.")
        default:
            return nil
        }
    }

    func parseGeneralConnectionError(_ error: Error) -> (message: String, details: String?) {
        // Match the error code before its text. `localizedDescription` is
        // localized, so on a phone that is not set to English none of the string
        // checks below can ever match and every failure looks identical.
        if let urlError = error as? URLError, let known = messageForURLError(urlError.code) {
            return known
        }

        let errorString = error.localizedDescription

        if errorString.contains("certificate") || errorString.contains("SSL") || errorString.contains("TLS") {
            return ("SSL/TLS certificate error", "Check if the server has a valid certificate or use http:// instead of https://")
        }
        if errorString.contains("Could not connect") || errorString.contains("Connection refused") {
            return ("Connection failed", "Check if the server is running and the URL is correct.")
        }
        if errorString.contains("timed out") || errorString.contains("timeout") {
            return ("Connection timed out", "The server did not respond in time. Check if the server is reachable.")
        }
        if errorString.contains("host") || errorString.contains("DNS") || errorString.contains("resolve") {
            return ("Server not found", "DNS resolution failed. Check the server URL.")
        }
        if errorString.contains("network") || errorString.contains("internet") {
            return ("Network error", "Check your internet connection.")
        }
        if errorString.contains("decode") || errorString.contains("JSON") || errorString.contains("invalid") {
            return ("Invalid response", "The server did not return a valid RomM response. Is this a RomM server?")
        }
        return ("Connection error", errorString)
    }

    func resetServerValidation() {
        serverValidated = false
        detectedServerVersion = nil
        connectionError = nil
        connectionErrorDetails = nil
        isErrorExpanded = false
        isVersionWarning = false
        versionWarningTitle = nil
        versionWarningDetails = nil
        didAcceptIncompatibleVersion = false
        // Abort any in-flight browser pairing — it's tied to the old server.
        cancelDeviceFlow()
        // NOTE: username/password are intentionally NOT cleared here
    }

    func performClassicLogin() async {
        isLoggingIn = true
        loginError = nil
        do {
            if let version = detectedServerVersion {
                saveServerVersionUseCase.execute(version: version)
            }
            _ = try await saveSetupConfigurationUseCase.execute(
                serverURL: serverURL,
                username: username,
                password: password,
                allowIncompatibleVersionLogin: didAcceptIncompatibleVersion
            )
            try SetupRepository().saveAuthMethod(.classic)
            Logger.auth.info("Classic login complete")
            await onAuthenticated()
        } catch {
            Logger.auth.error("Classic login failed: \(error)")
            loginError = error.localizedDescription
        }
        isLoggingIn = false
    }

    // MARK: - Client Token Login

    @MainActor
    func performClientTokenLogin() async {
        isExchangingToken = true
        clientTokenError = nil
        let service = ClientTokenAuthService()
        do {
            let tokenInfo = try await service.validateToken(serverURL: serverURL, token: clientTokenInput)
            try service.saveToken(clientTokenInput, info: tokenInfo)
            let setupRepo = SetupRepository()
            if let version = detectedServerVersion {
                saveServerVersionUseCase.execute(version: version)
            }
            try setupRepo.saveClientTokenSetup(
                serverURL: serverURL,
                tokenName: tokenInfo.name,
                version: detectedServerVersion ?? "unknown",
                allowIncompatibleVersionLogin: didAcceptIncompatibleVersion
            )
            Logger.auth.info("Client token login complete")
            await onAuthenticated()
        } catch {
            Logger.auth.error("Client token login failed: \(error)")
            clientTokenError = error.localizedDescription
        }
        isExchangingToken = false
    }

    @MainActor
    func performClientTokenPairing(code: String) async {
        isExchangingToken = true
        clientTokenError = nil
        let service = ClientTokenAuthService()
        do {
            let (token, tokenInfo) = try await service.exchangeCode(serverURL: serverURL, code: code)
            try service.saveToken(token, info: tokenInfo)
            let setupRepo = SetupRepository()
            if let version = detectedServerVersion {
                saveServerVersionUseCase.execute(version: version)
            }
            try setupRepo.saveClientTokenSetup(
                serverURL: serverURL,
                tokenName: tokenInfo.name,
                version: detectedServerVersion ?? "unknown",
                allowIncompatibleVersionLogin: didAcceptIncompatibleVersion
            )
            Logger.auth.info("Client token pairing complete")
            await onAuthenticated()
        } catch {
            Logger.auth.error("Client token pairing failed: \(error)")
            clientTokenError = error.localizedDescription
        }
        isExchangingToken = false
    }

    // MARK: - Device Flow Actions

    @MainActor
    func startDeviceFlow() async {
        hideKeyboard()
        deviceFlowError = nil

        if !serverValidated {
            await validateServer()
        }
        guard serverValidated && connectionError == nil else { return }

        if isVersionWarning {
            didAcceptIncompatibleVersion = true
            if let version = detectedServerVersion {
                onAcknowledgeVersion(version)
            }
        }

        // Server validated but doesn't offer the browser flow — point the user
        // at the fallback methods instead of failing silently.
        if let cap = detectedAuthCapability, !cap.deviceFlow {
            deviceFlowError = "This server doesn't support browser sign-in. Use another method below."
            withAnimation { showOtherOptions = true }
            return
        }

        isDeviceFlowRunning = true
        let service = DeviceAuthService()
        do {
            let info = try await service.initPairing(serverURL: serverURL)
            deviceFlowInit = info
            openApprovalBrowser(info: info)
            deviceFlowTask = Task { await pollDeviceFlow(service: service, info: info) }
        } catch {
            isDeviceFlowRunning = false
            deviceFlowInit = nil
            deviceFlowError = error.localizedDescription
        }
    }

    func openApprovalBrowser(info: DeviceAuthInitResponse) {
        guard let url = DeviceAuthService().verificationURL(serverURL: serverURL, init: info) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    func pollDeviceFlow(service: DeviceAuthService, info: DeviceAuthInitResponse) async {
        do {
            let token = try await service.pollForToken(serverURL: serverURL, init: info)
            await finishDeviceFlow(token: token)
        } catch {
            if case DeviceAuthError.cancelled = error {
                // User cancelled — no error message needed.
            } else {
                deviceFlowError = error.localizedDescription
            }
            isDeviceFlowRunning = false
            deviceFlowInit = nil
        }
    }

    @MainActor
    func finishDeviceFlow(token: DeviceAuthTokenResponse) async {
        let clientService = ClientTokenAuthService()
        let info = ClientTokenInfo(
            tokenId: 0,
            name: "Browser Sign-In",
            scopes: token.scopes,
            expiresAt: Self.parseISODate(token.expiresAt)
        )
        do {
            try clientService.saveToken(token.accessToken, info: info)
            // The device-flow token is bound to a server device — reuse its id
            // for the save-sync device layer so we don't register twice.
            UserDefaults.standard.set(token.deviceId, forKey: "sync.deviceId")

            let setupRepo = SetupRepository()
            if let version = detectedServerVersion {
                saveServerVersionUseCase.execute(version: version)
            }
            try setupRepo.saveClientTokenSetup(
                serverURL: serverURL,
                tokenName: info.name,
                version: detectedServerVersion ?? "unknown",
                allowIncompatibleVersionLogin: didAcceptIncompatibleVersion
            )
            Logger.auth.info("Browser device-flow login complete")
            isDeviceFlowRunning = false
            deviceFlowInit = nil
            await onAuthenticated()
        } catch {
            Logger.auth.error("Failed to store device-flow token: \(error)")
            deviceFlowError = error.localizedDescription
            isDeviceFlowRunning = false
            deviceFlowInit = nil
        }
    }

    func cancelDeviceFlow() {
        deviceFlowTask?.cancel()
        deviceFlowTask = nil
        isDeviceFlowRunning = false
        deviceFlowInit = nil
        deviceFlowError = nil
    }

    private static func parseISODate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    func preloadLastServerURL() {
        guard serverURL.isEmpty, !shouldShowLoginForUITests else { return }
        if let config = SetupRepository().getSetupConfiguration(), !config.serverURL.isEmpty {
            serverURL = config.serverURL
        }
    }

    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func insertText(_ text: String) {
        serverURL += text
    }

    func seedUITestLoginStateIfNeeded() {
        guard shouldShowLoginForUITests else { return }

        if serverURL.isEmpty { serverURL = "https://demo.romm.app" }
        if username.isEmpty { username = "snapshot-user" }
        if password.isEmpty { password = "snapshot-password" }

        detectedServerVersion = "3.0.0"
        serverValidated = true
        connectionError = nil
        connectionErrorDetails = nil
        isVersionWarning = false
        versionWarningTitle = nil
    }
}
