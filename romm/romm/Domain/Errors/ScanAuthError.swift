//
//  ScanAuthError.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

/// What can go wrong on the way to a scan session, beyond the credentials
/// themselves. A refused password never surfaces here, the session provider
/// asks again instead.
enum ScanAuthError: LocalizedError, Equatable {
    case serverNotConfigured
    case sessionCookieMissing

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "No server is configured."
        case .sessionCookieMissing:
            return "The server did not return a session, so the scan cannot be started."
        }
    }
}
