//
//  ScanSessionProvider.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  The one place that turns stored credentials into a `romm_session` cookie.
//  Everything else in the scan feature takes the cookie as given.
//

import Foundation

protocol PScanSessionProvider {
    /// A still-valid session cookie, signing in first if there is none.
    /// Throws `ScanAuthError.credentialsRequired` when the app has no password
    /// to sign in with, so the UI can ask for one.
    func sessionCookie() async throws -> String

    /// Stores the credentials the user typed into the scan prompt.
    func saveCredentials(username: String, password: String) throws

    /// Drops the cached cookie, e.g. after the server refused the session.
    func invalidate()
}

class ScanSessionProvider: PScanSessionProvider {
    /// Same Keychain store the client token lives in, no second credential
    /// store is introduced for the scan session.
    static let usernameKeychainKey = "romm.scanSession.username"
    static let passwordKeychainKey = "romm.scanSession.password"

    private let logger = Logger.auth
    private let apiClient: PRommAPIClient
    private let tokenProvider: PTokenProvider
    private let keychainService: PKeychainService

    /// Kept in memory only. The cookie is a credential and never goes to disk.
    private var cachedCookie: RommSessionCookie?

    init(
        apiClient: PRommAPIClient,
        tokenProvider: PTokenProvider,
        keychainService: PKeychainService = KeychainService.setup
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.keychainService = keychainService
    }

    func sessionCookie() async throws -> String {
        if let cachedCookie, Self.isValid(cachedCookie) {
            logger.debug("Reusing the cached scan session")
            return cachedCookie.headerValue
        }

        guard let credentials = storedCredentials() else {
            logger.info("No credentials available for a scan session")
            throw ScanAuthError.credentialsRequired
        }

        logger.info("Signing in for a scan session")
        do {
            let cookie = try await apiClient.login(
                username: credentials.username,
                password: credentials.password
            )
            cachedCookie = cookie
            return cookie.headerValue
        } catch APIClientError.authenticationRequired {
            // Whatever is stored no longer works, drop it so the UI asks again
            // instead of retrying the same rejected password forever.
            clearStoredCredentials()
            throw ScanAuthError.credentialsRejected
        }
    }

    func saveCredentials(username: String, password: String) throws {
        try keychainService.save(key: Self.usernameKeychainKey, value: username)
        try keychainService.save(key: Self.passwordKeychainKey, value: password)
        cachedCookie = nil
        logger.info("Stored scan session credentials in the keychain")
    }

    func invalidate() {
        cachedCookie = nil
    }

    // MARK: - Credentials

    /// A classic sign-in already has a password on hand, so nothing extra is
    /// asked for. Token and browser sign-ins fall back to what the user typed
    /// into the scan prompt.
    private func storedCredentials() -> (username: String, password: String)? {
        if let username = tokenProvider.getUsername(),
           let password = tokenProvider.getPassword(),
           !username.isEmpty, !password.isEmpty {
            return (username, password)
        }

        if let username = keychainService.get(key: Self.usernameKeychainKey),
           let password = keychainService.get(key: Self.passwordKeychainKey),
           !username.isEmpty, !password.isEmpty {
            return (username, password)
        }

        return nil
    }

    private func clearStoredCredentials() {
        cachedCookie = nil
        try? keychainService.delete(key: Self.usernameKeychainKey)
        try? keychainService.delete(key: Self.passwordKeychainKey)
    }

    /// A minute of headroom so a cookie never expires mid-handshake.
    private static func isValid(_ cookie: RommSessionCookie) -> Bool {
        guard let expiresAt = cookie.expiresAt else { return true }
        return expiresAt.timeIntervalSinceNow > 60
    }
}
