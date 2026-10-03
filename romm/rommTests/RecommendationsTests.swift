//
//  RecommendationsTests.swift
//  rommTests
//
//  Covers decoding RecommendedRomSchema from realistic server JSON, and
//  RomsRepository.getRecommendations mapping that into the domain model.
//

import Testing
import Foundation
@testable import romm

struct RecommendationsDecodingTests {

    private func decode(_ json: String) throws -> [RecommendedRomSchema] {
        try JSONDecoder().decode([RecommendedRomSchema].self, from: Data(json.utf8))
    }

    private func simpleRomJSON(id: Int, name: String) -> String {
        """
        {
          "id": \(id),
          "name": "\(name)",
          "platform_id": 3,
          "platform_slug": "gba",
          "platform_fs_slug": "gba",
          "platform_name": "Game Boy Advance",
          "platform_display_name": "Game Boy Advance",
          "fs_name": "\(name).gba",
          "fs_name_no_tags": "\(name)",
          "fs_name_no_ext": "\(name)",
          "fs_extension": "gba",
          "fs_path": "gba/\(name).gba",
          "fs_size_bytes": 1024,
          "alternative_names": [],
          "metadatum": {
            "rom_id": \(id),
            "genres": [],
            "franchises": [],
            "collections": [],
            "companies": [],
            "game_modes": [],
            "age_ratings": []
          },
          "path_cover_small": "resources/\(id)/cover_small.png",
          "has_manual": false,
          "is_unidentified": false,
          "is_identified": true,
          "regions": [],
          "languages": [],
          "tags": [],
          "files": [],
          "full_path": "gba/\(name).gba",
          "created_at": "2025-01-15T10:30:00Z",
          "updated_at": "2025-01-15T10:30:00Z",
          "missing_from_fs": false,
          "sibling_roms": [],
          "rom_user": {
            "id": 1,
            "user_id": 1,
            "rom_id": \(id),
            "created_at": "2025-01-15T10:30:00Z",
            "updated_at": "2025-01-15T10:30:00Z"
          }
        }
        """
    }

    @Test func decodesRecommendationsWithSeedRom() throws {
        let json = """
        [
          {
            "rom": \(simpleRomJSON(id: 1, name: "Metroid Fusion")),
            "score": 0.92,
            "reasons": [
              { "facet": "franchise", "value": "Metroid" },
              { "facet": "genre", "value": "Platformer" }
            ],
            "seed_rom_id": 42,
            "seed_rom_name": "Metroid Zero Mission"
          }
        ]
        """
        let recommendations = try decode(json)
        #expect(recommendations.count == 1)
        let first = recommendations[0]
        #expect(first.rom.id == 1)
        #expect(first.rom.name == "Metroid Fusion")
        #expect(first.score == 0.92)
        #expect(first.reasons.count == 2)
        #expect(first.reasons[0].facet == "franchise")
        #expect(first.reasons[0].value == "Metroid")
        #expect(first.seedRomId == 42)
        #expect(first.seedRomName == "Metroid Zero Mission")
    }

    @Test func seedRomFieldsDefaultToNilWhenMissing() throws {
        let json = """
        [
          {
            "rom": \(simpleRomJSON(id: 2, name: "Super Mario Advance")),
            "score": 0.5,
            "reasons": []
          }
        ]
        """
        let recommendations = try decode(json)
        #expect(recommendations.count == 1)
        #expect(recommendations[0].seedRomId == nil)
        #expect(recommendations[0].seedRomName == nil)
    }

    @Test func seedRomFieldsDecodeAsNilWhenExplicitlyNull() throws {
        let json = """
        [
          {
            "rom": \(simpleRomJSON(id: 3, name: "Golden Sun")),
            "score": 0.75,
            "reasons": [],
            "seed_rom_id": null,
            "seed_rom_name": null
          }
        ]
        """
        let recommendations = try decode(json)
        #expect(recommendations[0].seedRomId == nil)
        #expect(recommendations[0].seedRomName == nil)
    }

    @Test func unknownFacetValueDecodesAsPlainString() throws {
        let json = """
        [
          {
            "rom": \(simpleRomJSON(id: 4, name: "Fire Emblem")),
            "score": 0.6,
            "reasons": [
              { "facet": "a_future_facet_not_in_the_docs", "value": "something" }
            ],
            "seed_rom_name": "Fire Emblem: The Sacred Stones"
          }
        ]
        """
        let recommendations = try decode(json)
        #expect(recommendations[0].reasons.first?.facet == "a_future_facet_not_in_the_docs")
        #expect(recommendations[0].reasons.first?.value == "something")
    }
}

struct RomsRepositoryRecommendationsTests {

    @Test func mapsRecommendationsToDomainPreservingOrderAndSeedName() async throws {
        let api = FakeAPIClient()
        api.recommendationsToReturn = [
            RecommendedRomSchema(rom: makeSimpleRom(id: 10, name: "Chrono Trigger"), score: 0.9, reasons: [], seedRomId: 1, seedRomName: "Chrono Cross"),
            RecommendedRomSchema(rom: makeSimpleRom(id: 11, name: "Secret of Mana"), score: 0.8, reasons: [], seedRomId: nil, seedRomName: nil)
        ]
        let repository = RomsRepository(apiClient: api)

        let recommendations = try await repository.getRecommendations(limit: 10)

        #expect(api.recommendationsLimitRequested == 10)
        #expect(recommendations.count == 2)
        #expect(recommendations[0].rom.id == 10)
        #expect(recommendations[0].rom.name == "Chrono Trigger")
        #expect(recommendations[0].seedRomName == "Chrono Cross")
        #expect(recommendations[1].rom.id == 11)
        #expect(recommendations[1].rom.name == "Secret of Mana")
        #expect(recommendations[1].seedRomName == nil)
    }
}

private func makeSimpleRom(id: Int, name: String) -> SimpleRomSchema {
    SimpleRomSchema(
        id: id,
        igdbId: nil,
        sgdbId: nil,
        mobyId: nil,
        ssId: nil,
        raId: nil,
        launchboxId: nil,
        hasheousId: nil,
        tgdbId: nil,
        platformId: 1,
        platformSlug: "snes",
        platformFsSlug: "snes",
        platformName: "Super Nintendo",
        platformCustomName: nil,
        platformDisplayName: "Super Nintendo",
        fsName: "\(name).sfc",
        fsNameNoTags: name,
        fsNameNoExt: name,
        fsExtension: "sfc",
        fsPath: "snes/\(name).sfc",
        fsSizeBytes: 1024,
        name: name,
        slug: name.lowercased().replacingOccurrences(of: " ", with: "-"),
        summary: nil,
        alternativeNames: [],
        youtubeVideoId: nil,
        metadatum: RomMetadataSchema(
            romId: id,
            genres: [],
            franchises: [],
            collections: [],
            companies: [],
            gameModes: [],
            ageRatings: [],
            firstReleaseDate: nil,
            averageRating: nil
        ),
        igdbMetadata: nil,
        mobyMetadata: nil,
        ssMetadata: nil,
        launchboxMetadata: nil,
        hasheousMetadata: nil,
        pathCoverSmall: nil,
        pathCoverLarge: nil,
        urlCover: nil,
        hasManual: false,
        pathManual: nil,
        urlManual: nil,
        isUnidentified: false,
        isIdentified: true,
        revision: nil,
        regions: [],
        languages: [],
        tags: [],
        crcHash: nil,
        md5Hash: nil,
        sha1Hash: nil,
        multi: nil,
        files: [],
        fullPath: "snes/\(name).sfc",
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        missingFromFs: false,
        siblings: [],
        romUser: RomUserSchema(
            id: 1,
            userId: 1,
            romId: id,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            lastPlayed: nil,
            noteRawMarkdown: nil,
            noteIsPublic: nil,
            isMainSibling: nil,
            backlogged: false,
            nowPlaying: false,
            hidden: false,
            rating: 0,
            difficulty: 0,
            completion: 0,
            status: nil,
            userUsername: "user1"
        )
    )
}
