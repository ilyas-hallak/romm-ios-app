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

    private func decodeLossy(_ json: String) throws -> [RecommendedRomSchema] {
        try JSONDecoder().decode(LossyArray<RecommendedRomSchema>.self, from: Data(json.utf8)).elements
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
            "seed_rom_id": 42,
            "seed_rom_name": "Metroid Zero Mission"
          }
        ]
        """
        let recommendations = try decodeLossy(json)
        #expect(recommendations.count == 1)
        let first = recommendations[0]
        #expect(first.rom.id == 1)
        #expect(first.rom.name == "Metroid Fusion")
        #expect(first.seedRomName == "Metroid Zero Mission")
    }

    @Test func seedRomNameDefaultsToNilWhenMissing() throws {
        let json = """
        [
          {
            "rom": \(simpleRomJSON(id: 2, name: "Super Mario Advance"))
          }
        ]
        """
        let recommendations = try decodeLossy(json)
        #expect(recommendations.count == 1)
        #expect(recommendations[0].seedRomName == nil)
    }

    @Test func seedRomNameDecodesAsNilWhenExplicitlyNull() throws {
        let json = """
        [
          {
            "rom": \(simpleRomJSON(id: 3, name: "Golden Sun")),
            "seed_rom_name": null
          }
        ]
        """
        let recommendations = try decodeLossy(json)
        #expect(recommendations[0].seedRomName == nil)
    }

    @Test func skipsMalformedItemButKeepsValidOnesAroundIt() throws {
        let json = """
        [
          {
            "rom": \(simpleRomJSON(id: 1, name: "Metroid Fusion")),
            "seed_rom_name": "Metroid Zero Mission"
          },
          {
            "rom": { "name": "Missing Id" }
          },
          {
            "rom": \(simpleRomJSON(id: 3, name: "Golden Sun"))
          }
        ]
        """
        let recommendations = try decodeLossy(json)
        #expect(recommendations.map(\.rom.id) == [1, 3])
    }
}

struct RomsRepositoryRecommendationsTests {

    @Test func mapsRecommendationsToDomainPreservingOrderAndSeedName() async throws {
        let api = FakeAPIClient()
        api.recommendationsToReturn = [
            RecommendedRomSchema(rom: makeSimpleRom(id: 10, name: "Chrono Trigger"), seedRomName: "Chrono Cross"),
            RecommendedRomSchema(rom: makeSimpleRom(id: 11, name: "Secret of Mana"), seedRomName: nil)
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

    @Test func dedupesRecommendationsByRomIdKeepingFirstOccurrence() async throws {
        let api = FakeAPIClient()
        api.recommendationsToReturn = [
            RecommendedRomSchema(rom: makeSimpleRom(id: 10, name: "Chrono Trigger"), seedRomName: "Chrono Cross"),
            RecommendedRomSchema(rom: makeSimpleRom(id: 10, name: "Chrono Trigger"), seedRomName: "Secret of Mana"),
            RecommendedRomSchema(rom: makeSimpleRom(id: 11, name: "Secret of Mana"), seedRomName: nil)
        ]
        let repository = RomsRepository(apiClient: api)

        let recommendations = try await repository.getRecommendations(limit: 10)

        #expect(recommendations.map(\.rom.id) == [10, 11])
        #expect(recommendations[0].seedRomName == "Chrono Cross")
    }

    @Test func propagatesNetworkErrorWhenAPICallFails() async {
        let api = FakeAPIClient()
        api.errorToThrow = FakeAPIError()
        let repository = RomsRepository(apiClient: api)

        do {
            _ = try await repository.getRecommendations(limit: 10)
            Issue.record("expected RomError.networkError")
        } catch {
            #expect(error as? RomError == .networkError)
        }
    }
}
