//
//  LibraryScanStatus.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

enum LibraryScanState: Equatable {
    case queued
    case running
    case finished
    case failed
    case stopped
    case unknown
}

struct LibraryScanStats: Equatable, Hashable {
    let totalPlatforms: Int
    let totalRoms: Int
    let scannedPlatforms: Int
    let newPlatforms: Int
    let identifiedPlatforms: Int
    let scannedRoms: Int
    let newRoms: Int
    let identifiedRoms: Int
    let scannedFirmware: Int
    let newFirmware: Int
}

struct LibraryScanStatus: Equatable {
    let id: String
    /// The server's own label for the run, e.g. "Quick Scan" or "Complete Scan".
    let name: String
    let state: LibraryScanState
    let startedAt: Date?
    let endedAt: Date?
    let stats: LibraryScanStats?
}
