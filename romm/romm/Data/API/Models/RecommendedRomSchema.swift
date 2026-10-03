//
//  RecommendedRomSchema.swift
//  romm
//
//  DTO for GET /api/recommendations (RomM server 5.3+). Hand-written rather than
//  generated, since the recommendations endpoint isn't part of the OpenAPI spec yet.
//

import Foundation

public struct SimilarityReasonSchema: Codable, Hashable {
    public var facet: String
    public var value: String

    public init(facet: String, value: String) {
        self.facet = facet
        self.value = value
    }

    public enum CodingKeys: String, CodingKey {
        case facet
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // facet is a String on purpose: new facet values from the server must not
        // break decoding, so no enum with a fixed case list is used here.
        facet = container.decodeFlexibleString(forKey: .facet, default: "")
        value = container.decodeFlexibleString(forKey: .value, default: "")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(facet, forKey: .facet)
        try container.encode(value, forKey: .value)
    }
}

public struct RecommendedRomSchema: Codable, Hashable {
    public var rom: SimpleRomSchema
    public var score: Double
    public var reasons: [SimilarityReasonSchema]
    public var seedRomId: Int?
    public var seedRomName: String?

    public init(rom: SimpleRomSchema, score: Double, reasons: [SimilarityReasonSchema], seedRomId: Int?, seedRomName: String?) {
        self.rom = rom
        self.score = score
        self.reasons = reasons
        self.seedRomId = seedRomId
        self.seedRomName = seedRomName
    }

    public enum CodingKeys: String, CodingKey {
        case rom
        case score
        case reasons
        case seedRomId = "seed_rom_id"
        case seedRomName = "seed_rom_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rom = try container.decode(SimpleRomSchema.self, forKey: .rom)
        score = container.decodeIfPresentOrDefault(Double.self, forKey: .score, default: 0)
        reasons = container.decodeLossyArray(SimilarityReasonSchema.self, forKey: .reasons)
        seedRomId = try container.decodeIfPresent(Int.self, forKey: .seedRomId)
        seedRomName = try container.decodeIfPresent(String.self, forKey: .seedRomName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rom, forKey: .rom)
        try container.encode(score, forKey: .score)
        try container.encode(reasons, forKey: .reasons)
        try container.encodeIfPresent(seedRomId, forKey: .seedRomId)
        try container.encodeIfPresent(seedRomName, forKey: .seedRomName)
    }
}
