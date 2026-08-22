//
//  CollectionSchemaDecodingTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

struct CollectionSchemaDecodingTests {

    // The API client decodes with a plain JSONDecoder; CollectionSchema resolves
    // keys and dates itself in init(from:).
    private func decode(usernameField: String?) throws -> CollectionSchema {
        var json = """
        {
          "name": "My Collection",
          "rom_ids": [1, 2, 3],
          "rom_count": 3,
          "created_at": "2025-01-15T10:30:00Z",
          "updated_at": "2025-01-16T11:00:00Z",
          "id": 42,
          "user_id": 7
        """
        if let usernameField {
            json += ",\n  \(usernameField)"
        }
        json += "\n}"
        return try JSONDecoder().decode(CollectionSchema.self, from: Data(json.utf8))
    }

    @Test func decodesOwnerUsernameFromRomM5Payload() throws {
        let collection = try decode(usernameField: #""owner_username": "ilyas""#)
        #expect(collection.userUsername == "ilyas")
    }

    @Test func decodesLegacyUserUsernameFromRomM4Payload() throws {
        let collection = try decode(usernameField: #""user__username": "ilyas""#)
        #expect(collection.userUsername == "ilyas")
    }

    @Test func decodesEmptyUsernameWhenBothKeysAreMissing() throws {
        let collection = try decode(usernameField: nil)
        #expect(collection.userUsername == "")
    }
}
