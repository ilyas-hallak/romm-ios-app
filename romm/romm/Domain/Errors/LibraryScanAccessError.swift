//
//  LibraryScanAccessError.swift
//  romm
//
//  `tasks.run` is granted by the account's role but not always by the current
//  sign-in's token: a device-flow pairing from before this scope was added to
//  `DeviceAuthService.defaultScopes` never requested it, so the server still
//  answers 403 even though the role, and so the scan entry point, allow it.
//

import Foundation

enum LibraryScanAccessError: Error, LocalizedError, Equatable {
    case missingScope

    var errorDescription: String? {
        switch self {
        case .missingScope:
            return "This sign-in doesn't have permission to manage scans. Sign out and reconnect to pick up the updated permissions."
        }
    }

    /// `GET /api/tasks/status` and `POST /api/tasks/scan` both require the
    /// `tasks.run` scope, so a 403 from either one only ever means this.
    static func mapIfMissingScope(_ error: Error) -> Error {
        if case APIClientError.invalidResponse(403, _) = error {
            return LibraryScanAccessError.missingScope
        }
        return error
    }
}
