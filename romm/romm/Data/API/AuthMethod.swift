//
//  AuthMethod.swift
//  romm
//
//  Authentication Method Enumeration
//

import Foundation

/// Authentication methods supported by the app
enum AuthMethod: String, Codable, CaseIterable {
    /// Browser-based device authorization (RomM 5.x). Approve in the browser,
    /// the app receives a bound client token. No password typed in the app.
    case deviceFlow

    /// Classic username/password authentication (Basic Auth)
    case classic

    /// Client API Token authentication (prefixed with `rmm_`)
    case clientToken

    /// User-friendly display name
    var displayName: String {
        switch self {
        case .deviceFlow:
            return "Browser Sign-In"
        case .classic:
            return "Username & Password"
        case .clientToken:
            return "API Token"
        }
    }

    /// Short description
    var description: String {
        switch self {
        case .deviceFlow:
            return "Approve this device in your browser — no password needed"
        case .classic:
            return "Traditional login with username and password"
        case .clientToken:
            return "Connect with an API token from your server"
        }
    }

    /// Icon name for UI
    var iconName: String {
        switch self {
        case .deviceFlow:
            return "safari"
        case .classic:
            return "person.fill"
        case .clientToken:
            return "key.fill"
        }
    }

    /// Whether this method requires a browser
    var requiresBrowser: Bool {
        self == .deviceFlow
    }

    /// Whether this method stores credentials locally
    var storesCredentials: Bool {
        switch self {
        case .deviceFlow:
            return false // Bound client token stored in Keychain
        case .classic:
            return true // Username stored, password used for Basic Auth
        case .clientToken:
            return false // Token stored in Keychain, not as credential
        }
    }
}

// MARK: - Helper Extensions

extension AuthMethod {
    /// Returns a recommendation string based on rich auth capabilities
    static func recommendation(for capabilities: HeartbeatRepository.AuthCapabilities) -> String {
        if capabilities.unreachable { return "Server is unreachable" }
        if capabilities.cloudflareBlocked { return "Server is protected by Cloudflare" }
        return "Choose your preferred authentication method"
    }

    /// Returns available methods based on rich auth capabilities, most-recommended
    /// first. Browser sign-in leads when the server supports it.
    static func availableMethods(for capabilities: HeartbeatRepository.AuthCapabilities) -> [AuthMethod] {
        var methods: [AuthMethod] = []
        if capabilities.deviceFlow { methods.append(.deviceFlow) }
        if capabilities.classic { methods.append(.classic) }
        if capabilities.clientTokens { methods.append(.clientToken) }
        return methods
    }
}
