//
//  ScanStartError.swift
//  romm
//
//  What the server answers when `POST /api/tasks/scan` declines to queue a
//  scan: one is already running, or no worker is listening. Not a failure,
//  just a notice to show next to the start button.
//

import Foundation

enum ScanStartError: Error, LocalizedError, Equatable {
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .refused(let message): return message
        }
    }
}
