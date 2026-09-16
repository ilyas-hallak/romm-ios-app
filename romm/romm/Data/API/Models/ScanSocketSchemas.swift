//
//  ScanSocketSchemas.swift
//  romm
//
//  DTOs for the payloads a running scan pushes over Socket.IO (issue #160).
//  These payloads are large and differ between server versions, so every field
//  is optional and nothing here ever throws while decoding.
//

import Foundation

struct ScanPlatformSchema: Decodable {
    let id: Int?
    let name: String?
    let displayName: String?
    let slug: String?
    let fsSlug: String?
    let isIdentified: Bool?
    let newFirmwareCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayName = "display_name"
        case slug
        case fsSlug = "fs_slug"
        case isIdentified = "is_identified"
        case newFirmwareCount = "new_firmware_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(Int.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        displayName = try? container.decodeIfPresent(String.self, forKey: .displayName)
        slug = try? container.decodeIfPresent(String.self, forKey: .slug)
        fsSlug = try? container.decodeIfPresent(String.self, forKey: .fsSlug)
        isIdentified = try? container.decodeIfPresent(Bool.self, forKey: .isIdentified)
        newFirmwareCount = try? container.decodeIfPresent(Int.self, forKey: .newFirmwareCount)
    }
}

struct ScanRomSchema: Decodable {
    let id: Int?
    let name: String?
    let fsName: String?
    let platformName: String?
    let platformSlug: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fsName = "fs_name"
        case platformName = "platform_name"
        case platformSlug = "platform_slug"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(Int.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        fsName = try? container.decodeIfPresent(String.self, forKey: .fsName)
        platformName = try? container.decodeIfPresent(String.self, forKey: .platformName)
        platformSlug = try? container.decodeIfPresent(String.self, forKey: .platformSlug)
    }
}
