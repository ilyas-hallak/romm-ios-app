//
//  LibraryScanEvent.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  What a running scan reports back, one value per socket event. The payloads
//  the server sends are large and vary by version, so everything that is not
//  needed for the live view is dropped in the mapper.
//

import Foundation

struct LibraryScanPlatform: Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let displayName: String
    let slug: String
    let isIdentified: Bool
    let newFirmwareCount: Int
}

/// One ROM as it comes in during a scan. The identity is per arrival, not per
/// ROM: the live feed is chronological and the same ROM can show up twice.
struct LibraryScanRom: Identifiable, Equatable, Hashable {
    let id: UUID
    let romId: Int?
    let name: String
    let fileName: String?
    let platformName: String?

    init(id: UUID = UUID(), romId: Int?, name: String, fileName: String?, platformName: String?) {
        self.id = id
        self.romId = romId
        self.name = name
        self.fileName = fileName
        self.platformName = platformName
    }
}

enum LibraryScanEvent: Equatable {
    case platform(LibraryScanPlatform)
    case rom(LibraryScanRom)
    case stats(LibraryScanStats)
    case finished
    case failed(String)
}
