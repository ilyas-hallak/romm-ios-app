//
//  ScanAuthError.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

/// Starting a scan needs a server session, which only a username and password
/// can create. Token and browser sign-ins do not carry one, hence the extra
/// prompt these errors drive.
enum ScanAuthError: LocalizedError, Equatable {
    case credentialsRequired
    case credentialsRejected
    case serverNotConfigured
    case sessionCookieMissing

    var errorDescription: String? {
        switch self {
        case .credentialsRequired:
            return "Starting a scan needs your RomM username and password."
        case .credentialsRejected:
            return "The server did not accept these credentials."
        case .serverNotConfigured:
            return "No server is configured."
        case .sessionCookieMissing:
            return "The server did not return a session, so the scan cannot be started."
        }
    }
}
