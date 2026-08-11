//
//  DeviceAuthModels.swift
//  romm
//
//  DTOs for the RomM device-authorization pairing flow (RomM 5.x).
//
//  Flow (verified against a 5.1.0 server):
//    1. POST /api/auth/device/init   → device_code + user_code + verification path
//    2. User approves in the browser at {serverURL}/pair/device?user_code=…
//    3. POST /api/auth/device/token  → polled until it returns an access_token
//
//  The access_token returned in step 3 is a bound client token, so it is stored
//  and used exactly like a pasted client token (Bearer auth, Keychain).
//

import Foundation

// MARK: - Init

/// Request body for `POST /api/auth/device/init`.
struct DeviceAuthInitRequest: Encodable {
    /// Stable per-install identifier so the server can recognize/reset this device.
    let clientDeviceIdentifier: String
    /// Human-readable device name shown on the approval screen (e.g. the device name).
    let name: String
    /// Client identifier string (e.g. "romm-ios").
    let client: String
    let platform: String?
    let clientVersion: String?
    /// OAuth-style scopes the app is asking for. Server requires 1…22 items.
    let requestedScopes: [String]

    enum CodingKeys: String, CodingKey {
        case clientDeviceIdentifier = "client_device_identifier"
        case name
        case client
        case platform
        case clientVersion = "client_version"
        case requestedScopes = "requested_scopes"
    }
}

/// Response for `POST /api/auth/device/init`.
struct DeviceAuthInitResponse: Decodable {
    let deviceCode: String
    let userCode: String
    /// Relative web-UI path, e.g. "/pair/device". Joined with the server origin.
    let verificationPath: String
    /// Same path with `?user_code=` appended — convenient for opening directly.
    let verificationPathComplete: String
    /// Seconds until the pairing request expires.
    let expiresIn: Int
    /// Recommended seconds between polls.
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationPath = "verification_path"
        case verificationPathComplete = "verification_path_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

// MARK: - Token polling

/// Request body for `POST /api/auth/device/token`.
struct DeviceAuthTokenRequest: Encodable {
    let deviceCode: String

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
    }
}

/// Success response for `POST /api/auth/device/token` (HTTP 200).
struct DeviceAuthTokenResponse: Decodable {
    /// The client token string used for subsequent Bearer auth.
    let accessToken: String
    /// Server device id — the same identity used by the save-sync device APIs.
    let deviceId: String
    let scopes: [String]
    /// ISO-8601 expiry, or null for a non-expiring token.
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case deviceId = "device_id"
        case scopes
        case expiresAt = "expires_at"
    }
}

// MARK: - Errors

/// Errors surfaced by the device-authorization flow. Messages are user-facing.
enum DeviceAuthError: LocalizedError {
    /// The user approved on the web but the request had already expired.
    case expired
    /// The user explicitly denied the pairing request in the browser.
    case denied
    /// Polling was cancelled (e.g. the user tapped Cancel).
    case cancelled
    /// Invalid server URL.
    case invalidURL
    /// Transport / decoding failure with a description for the debug panel.
    case network(String)

    var errorDescription: String? {
        switch self {
        case .expired:
            return "The pairing request expired. Please try signing in again."
        case .denied:
            return "The sign-in request was denied on the server."
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidURL:
            return "The server URL is not valid."
        case .network(let message):
            return message
        }
    }
}

/// Standard OAuth device-flow `detail` codes returned as HTTP 400 while polling.
enum DeviceAuthPollStatus {
    case pending
    case slowDown
    case denied
    case expired

    init?(detail: String) {
        switch detail {
        case "authorization_pending": self = .pending
        case "slow_down": self = .slowDown
        case "access_denied": self = .denied
        case "expired_token": self = .expired
        default: return nil
        }
    }
}
