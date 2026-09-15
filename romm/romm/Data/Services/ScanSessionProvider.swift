//
//  ScanSessionProvider.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  The one place that turns stored credentials into a `romm_session` cookie,
//  asking the user for a password itself when it has none. Everything else in
//  the scan feature takes the cookie as given and knows nothing about how it
//  came to be.
//

import Foundation

protocol PScanSessionProvider {
    /// A still-valid session cookie, signing in first if there is none and
    /// asking the user for credentials if the app has none on hand.
    /// Throws `CancellationError` when the user dismissed that prompt.
    func sessionCookie() async throws -> String

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
    private let credentialsPrompt: PScanCredentialsPrompt

    /// Kept in memory only. The cookie is a credential and never goes to disk.
    private var cachedCookie: RommSessionCookie?

    init(
        apiClient: PRommAPIClient,
        tokenProvider: PTokenProvider,
        credentialsPrompt: PScanCredentialsPrompt,
        keychainService: PKeychainService = KeychainService.setup
    ) {
        self.apiClient = apiClient
        self.tokenProvider = tokenProvider
        self.credentialsPrompt = credentialsPrompt
        self.keychainService = keychainService
    }

    func sessionCookie() async throws -> String {
        if let cachedCookie, Self.isValid(cachedCookie) {
            logger.debug("Reusing the cached scan session")
            return cachedCookie.headerValue
        }

        // Loops so a rejected password leads straight back to the prompt
        // instead of failing the scan the user just asked for.
        var retryReason: String?
        while true {
            guard let credentials = await resolveCredentials(retryReason: retryReason) else {
                logger.info("The user dismissed the scan credentials prompt")
                throw CancellationError()
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
                // Whatever was stored no longer works, drop it so the next turn
                // asks instead of retrying the same rejected password forever.
                clearStoredCredentials()
                retryReason = "The server did not accept these credentials."
            }
        }
    }

    func invalidate() {
        cachedCookie = nil
    }

    // MARK: - Credentials

    /// Stored credentials first, the user second. After a rejection the stored
    /// ones are skipped, they are what was just refused.
    private func resolveCredentials(retryReason: String?) async -> ScanCredentials? {
        if retryReason == nil, let stored = storedCredentials() {
            return stored
        }

        guard let typed = await credentialsPrompt.credentials(retryReason: retryReason) else {
            return nil
        }

        save(typed)
        return typed
    }

    /// A classic sign-in already has a password on hand, so nothing extra is
    /// asked for. Token and browser sign-ins fall back to what the user typed
    /// into the scan prompt.
    private func storedCredentials() -> ScanCredentials? {
        if let username = tokenProvider.getUsername(),
           let password = tokenProvider.getPassword(),
           !username.isEmpty, !password.isEmpty {
            return ScanCredentials(username: username, password: password)
        }

        if let username = keychainService.get(key: Self.usernameKeychainKey),
           let password = keychainService.get(key: Self.passwordKeychainKey),
           !username.isEmpty, !password.isEmpty {
            return ScanCredentials(username: username, password: password)
        }

        return nil
    }

    private func save(_ credentials: ScanCredentials) {
        do {
            try keychainService.save(key: Self.usernameKeychainKey, value: credentials.username)
            try keychainService.save(key: Self.passwordKeychainKey, value: credentials.password)
            cachedCookie = nil
            logger.info("Stored scan session credentials in the keychain")
        } catch {
            // Not fatal: the scan still runs with what the user just typed, it
            // just has to be typed again next time.
            logger.warning("Could not store the scan session credentials: \(error)")
        }
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
