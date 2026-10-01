//
//  ClientTokenAuthService.swift
//  romm
//
//  Client Token Authentication Service
//  Handles QR/deep-link pairing, token validation, and Keychain storage
//

import Foundation

// MARK: - Error Types

enum ClientTokenError: LocalizedError {
    case invalidQRCode
    case codeExpired
    case codeInvalid
    case exchangeFailed(String)
    case tokenInvalid
    case tokenSaveFailed
    case scopeFetchFailed
    case cameraUnavailable
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .invalidQRCode:
            return "The QR code is not a valid RomM pairing code."
        case .codeExpired:
            return "The pairing code has expired. Please generate a new one."
        case .codeInvalid:
            return "The pairing code is invalid."
        case .exchangeFailed(let message):
            return "Failed to exchange pairing code: \(message)"
        case .tokenInvalid:
            return "The client token is invalid or revoked."
        case .tokenSaveFailed:
            return "Failed to save the client token to Keychain."
        case .scopeFetchFailed:
            return "Failed to fetch token scope information."
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .rateLimited:
            return "Too many attempts. Please wait before trying again."
        }
    }
}

// MARK: - ClientTokenAuthService

class ClientTokenAuthService {

    private let logger = Logger.auth
    private let keychainService: PKeychainService

    static let tokenKeychainKey = "romm.clientToken"
    static let tokenInfoKeychainKey = "romm.clientTokenInfo"

    init(keychainService: PKeychainService = KeychainService.setup) {
        self.keychainService = keychainService
    }
}

// MARK: - Deep Link Handling

extension ClientTokenAuthService {

    /// Parses a `romm://pair?code=XXXXXXXX` deep link and returns the 8-character pairing code.
    func handleDeepLink(url: URL) -> String? {
        guard url.scheme == "romm",
              url.host == "pair",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let codeItem = components.queryItems?.first(where: { $0.name == "code" }),
              let code = codeItem.value,
              code.count == 8 else {
            logger.warning("Invalid deep link URL: \(url.absoluteString)")
            return nil
        }
        logger.info("Parsed pairing code from deep link")
        return code
    }
}

// MARK: - Pairing Flow

extension ClientTokenAuthService {

    /// Exchanges a pairing code for a client token via the server API.
    /// Returns the raw token string and the token info (from the exchange response).
    func exchangeCode(serverURL: String, code: String) async throws -> (token: String, info: ClientTokenInfo) {
        let cleanURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(cleanURL)/api/client-tokens/exchange"

        guard let url = URL(string: endpoint) else {
            throw ClientTokenError.exchangeFailed("Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15.0

        let body = ["code": code]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.info("Exchanging pairing code with server")

        let session = URLSession(
            configuration: .default.withoutCookies(),
            delegate: PrivateNetworkURLSessionDelegate(),
            delegateQueue: nil
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientTokenError.exchangeFailed("Invalid response")
        }

        logger.debug("Exchange response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 404, 410:
            throw ClientTokenError.codeExpired
        case 400:
            throw ClientTokenError.codeInvalid
        case 429:
            throw ClientTokenError.rateLimited
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClientTokenError.exchangeFailed("HTTP \(httpResponse.statusCode): \(message)")
        }

        // Log raw response for debugging
        let rawResponse = String(data: data, encoding: .utf8) ?? "non-utf8"
        logger.debug("Exchange raw response: \(rawResponse)")

        // Response contains the full token object with "raw_token" field
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientTokenError.exchangeFailed("Invalid response format")
        }

        // The raw token string is in "raw_token"
        guard let rawToken = json["raw_token"] as? String else {
            throw ClientTokenError.exchangeFailed("No raw_token in response")
        }

        // Parse token info from the same response
        let tokenId = json["id"] as? Int ?? 0
        let name = json["name"] as? String ?? "Token"

        let scopes: [String]
        if let scopesArray = json["scopes"] as? [String] {
            scopes = scopesArray
        } else if let scopesString = json["scopes"] as? String {
            scopes = scopesString.components(separatedBy: " ").filter { !$0.isEmpty }
        } else {
            scopes = []
        }

        var expiresAt: Date?
        if let expiresStr = json["expires_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiresAt = formatter.date(from: expiresStr)
            if expiresAt == nil {
                formatter.formatOptions = [.withInternetDateTime]
                expiresAt = formatter.date(from: expiresStr)
            }
        }

        let info = ClientTokenInfo(tokenId: tokenId, name: name, scopes: scopes, expiresAt: expiresAt)

        logger.info("Pairing code exchanged successfully: \(info.name) with \(info.scopes.count) scope(s)")
        return (token: rawToken, info: info)
    }
}

// MARK: - Direct Token Validation

extension ClientTokenAuthService {

    /// Validates a client token against the server and returns its info.
    func validateToken(serverURL: String, token: String) async throws -> ClientTokenInfo {
        let cleanURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(cleanURL)/api/client-tokens"

        guard let url = URL(string: endpoint) else {
            throw ClientTokenError.scopeFetchFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15.0

        let session = URLSession(
            configuration: .default.withoutCookies(),
            delegate: PrivateNetworkURLSessionDelegate(),
            delegateQueue: nil
        )

        logger.info("Validating client token with server")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientTokenError.scopeFetchFailed
        }

        logger.debug("Token validation response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "non-utf8"
            logger.error("Token validation failed - HTTP \(httpResponse.statusCode): \(body)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw ClientTokenError.tokenInvalid
            }
            throw ClientTokenError.scopeFetchFailed
        }

        // Log raw response for debugging
        let rawResponse = String(data: data, encoding: .utf8) ?? "non-utf8"
        logger.debug("Token validation raw response: \(rawResponse)")

        // Try to parse the response — server may return an array or a single object
        // Fields may vary by server version
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ??
                  (try JSONSerialization.jsonObject(with: data) as? [String: Any]).map({ [$0] }) else {
                logger.error("Response is neither array nor object")
                throw ClientTokenError.scopeFetchFailed
            }

            guard let first = json.first else {
                throw ClientTokenError.tokenInvalid
            }

            let tokenId = first["id"] as? Int ?? 0
            let name = first["name"] as? String ?? "Token"

            // Scopes can be an array of strings or a space-separated string
            let scopes: [String]
            if let scopesArray = first["scopes"] as? [String] {
                scopes = scopesArray
            } else if let scopesString = first["scopes"] as? String {
                scopes = scopesString.components(separatedBy: " ").filter { !$0.isEmpty }
            } else {
                scopes = []
            }

            // Parse expires_at — could be ISO 8601 string or null
            var expiresAt: Date?
            if let expiresStr = first["expires_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                expiresAt = formatter.date(from: expiresStr)
                if expiresAt == nil {
                    // Try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    expiresAt = formatter.date(from: expiresStr)
                }
            }

            let info = ClientTokenInfo(
                tokenId: tokenId,
                name: name,
                scopes: scopes,
                expiresAt: expiresAt
            )

            logger.info("Token validated: \(info.name) with \(info.scopes.count) scope(s)")
            return info
        } catch let error as ClientTokenError {
            throw error
        } catch {
            logger.error("Failed to parse token validation response: \(error)")
            throw ClientTokenError.scopeFetchFailed
        }
    }

    /// Convenience wrapper that delegates to `validateToken`.
    func fetchTokenInfo(serverURL: String, token: String) async throws -> ClientTokenInfo {
        return try await validateToken(serverURL: serverURL, token: token)
    }
}

// MARK: - Token Storage

extension ClientTokenAuthService {

    /// Saves the client token string and its info to the Keychain.
    func saveToken(_ token: String, info: ClientTokenInfo) throws {
        do {
            try keychainService.save(key: Self.tokenKeychainKey, value: token)
        } catch {
            logger.error("Failed to save client token to Keychain: \(error.localizedDescription)")
            throw ClientTokenError.tokenSaveFailed
        }

        do {
            let data = try JSONEncoder().encode(info)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw ClientTokenError.tokenSaveFailed
            }
            try keychainService.save(key: Self.tokenInfoKeychainKey, value: jsonString)
        } catch let error as ClientTokenError {
            throw error
        } catch {
            logger.error("Failed to save client token info to Keychain: \(error.localizedDescription)")
            throw ClientTokenError.tokenSaveFailed
        }

        logger.info("Client token and info saved to Keychain")
    }

    /// Reads the stored client token string from the Keychain.
    func getToken() -> String? {
        return keychainService.get(key: Self.tokenKeychainKey)
    }

    /// Reads and decodes the stored `ClientTokenInfo` from the Keychain.
    func getTokenInfo() -> ClientTokenInfo? {
        guard let jsonString = keychainService.get(key: Self.tokenInfoKeychainKey),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ClientTokenInfo.self, from: data)
    }

    /// Deletes both the token and token info from the Keychain.
    func clearToken() {
        try? keychainService.delete(key: Self.tokenKeychainKey)
        try? keychainService.delete(key: Self.tokenInfoKeychainKey)
        logger.info("Client token cleared from Keychain")
    }
}
