//
//  HeartbeatError.swift
//  romm
//

import Foundation

enum HeartbeatError: LocalizedError {
    case serverVersionChanged(from: String, to: String)
    case serverVersionTooLow(serverVersion: String, minRequired: String)
    case serverVersionTooHigh(serverVersion: String, maxSupported: String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .serverVersionChanged(let from, let to):
            return "Server was updated (from \(from) to \(to)). Please login again."
        case .serverVersionTooLow(let serverVersion, let minRequired):
            return "Server version \(serverVersion) is too old. Minimum required: \(minRequired)"
        case .serverVersionTooHigh(let serverVersion, _):
            return "Your server has been updated to version \(serverVersion), but this app doesn't support it yet. An app update is coming soon."
        case .decodingError(let error):
            return "Invalid server response: \(error.localizedDescription)"
        case .networkError(let error):
            return error.localizedDescription
        }
    }
}
