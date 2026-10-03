//
//  RecommendedRomSchema.swift
//  romm
//
//  DTO for GET /api/recommendations (RomM server 5.3+). Hand-written rather than
//  generated, since the recommendations endpoint isn't part of the OpenAPI spec yet.
//

import Foundation

public struct RecommendedRomSchema: Decodable {
    public var rom: SimpleRomSchema
    public var seedRomName: String?

    public init(rom: SimpleRomSchema, seedRomName: String?) {
        self.rom = rom
        self.seedRomName = seedRomName
    }

    public enum CodingKeys: String, CodingKey {
        case rom
        case seedRomName = "seed_rom_name"
    }
}
