//
//  ScanStartRequest.swift
//  romm
//
//  Body for `POST /api/tasks/scan` (RomM 5.4.0, #5014 upstream). Mirrors the
//  `scan` socket event's options, but the server validates this one strictly,
//  an unknown key is rejected rather than ignored.
//

import Foundation

struct ScanStartRequest: Encodable {
    let type: String
    let platforms: [Int]
    let platformFsSlugs: [String]
    let romsIds: [Int]
    let apis: [String]
    let launchboxRemoteEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case platforms
        case platformFsSlugs = "platform_fs_slugs"
        case romsIds = "roms_ids"
        case apis
        case launchboxRemoteEnabled = "launchbox_remote_enabled"
    }
}
