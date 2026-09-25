//
//  UserSchemaDecodingTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

struct UserSchemaDecodingTests {

    private func decode(role: String) throws -> UserSchema {
        let json = """
        {
          "id": 1,
          "username": "tester",
          "email": "tester@example.com",
          "enabled": true,
          "role": "\(role)",
          "oauth_scopes": [],
          "avatar_path": "",
          "created_at": "2025-01-15T10:30:00Z",
          "updated_at": "2025-01-16T11:00:00Z"
        }
        """
        return try JSONDecoder().decode(UserSchema.self, from: Data(json.utf8))
    }

    @Test func decodesUserRoleFromRomM52Payload() throws {
        // 5.2+ servers collapsed viewer/editor into a single "user" role.
        let user = try decode(role: "user")
        #expect(user.role == .user)
        #expect(UserMapper.mapFromAPI(user).role == .user)
    }

    @Test func decodesLegacyViewerRoleFromRomM4Payload() throws {
        let user = try decode(role: "viewer")
        #expect(user.role == .viewer)
        #expect(UserMapper.mapFromAPI(user).role == .viewer)
    }

    @Test func decodesUnknownRoleAsUserInsteadOfFailing() throws {
        // A role this app doesn't know yet must not fail decoding of the
        // whole user, since that would break login for that account.
        let user = try decode(role: "totally_new_role")
        #expect(user.role == .user)
        #expect(UserMapper.mapFromAPI(user).role == .user)
    }
}
