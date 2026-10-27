//
//  RomFileSchemaDecodingTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

struct RomFileSchemaDecodingTests {

    private func decode(category: String?, lastModified: String?) throws -> RomFileSchema {
        var json = """
        {
          "id": 1,
          "rom_id": 42,
          "file_name": "game.zip",
          "file_path": "platform/game.zip",
          "file_size_bytes": 1024,
          "full_path": "platform/game.zip",
          "created_at": "2025-01-15T10:30:00Z",
          "updated_at": "2025-01-16T11:00:00Z"
        """
        if let lastModified {
            json += ",\n  \"last_modified\": \"\(lastModified)\""
        } else {
            json += ",\n  \"last_modified\": null"
        }
        if let category {
            json += ",\n  \"category\": \"\(category)\""
        }
        json += "\n}"
        return try JSONDecoder().decode(RomFileSchema.self, from: Data(json.utf8))
    }

    @Test func decodesKnownGameCategory() throws {
        let file = try decode(category: "game", lastModified: "2025-01-16T11:00:00Z")
        #expect(file.category == .game)
    }

    @Test func decodesUnknownCategoryInsteadOfFailing() throws {
        // A category the server adds after this app ships must not drop the
        // whole file entry (it used to, via decodeLossyArray).
        let file = try decode(category: "some_future_category", lastModified: "2025-01-16T11:00:00Z")
        #expect(file.category == .unknown)
    }

    @Test func decodesNullLastModifiedAsNil() throws {
        let file = try decode(category: "game", lastModified: nil)
        #expect(file.lastModified == nil)
    }
}
