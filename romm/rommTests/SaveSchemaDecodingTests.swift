//
//  SaveSchemaDecodingTests.swift
//  rommTests
//
//  SaveSchema and DeviceSyncSchema both parse their own `init(from:)`, so
//  they're tested against hand-written server JSON rather than through the
//  memberwise init, the same way CollectionSchemaDecodingTests covers
//  CollectionSchema.
//

import Foundation
import Testing
@testable import romm

struct SaveSchemaDecodingTests {

    // MARK: - JSON builders

    // `createdAt`/`updatedAt` are dedicated parameters rather than something
    // callers pass through `extra`: `extra` is only ever appended after the
    // base fields, so overriding created_at/updated_at through it would
    // produce a JSON object with that key twice.
    private func decode(
        createdAt: String = "2025-01-15T10:30:00Z",
        updatedAt: String = "2025-01-16T11:00:00Z",
        saveFields extra: String = ""
    ) throws -> SaveSchema {
        var json = """
        {
          "id": 99,
          "rom_id": 1,
          "user_id": 7,
          "file_name": "game.srm",
          "file_name_no_tags": "game",
          "file_name_no_ext": "game",
          "file_extension": "srm",
          "file_path": "saves/game.srm",
          "file_size_bytes": 10,
          "full_path": "saves/game.srm",
          "download_path": "/api/saves/99/content",
          "missing_from_fs": false,
          "created_at": "\(createdAt)",
          "updated_at": "\(updatedAt)"
        """
        if !extra.isEmpty { json += ",\n\(extra)" }
        json += "\n}"
        return try JSONDecoder().decode(SaveSchema.self, from: Data(json.utf8))
    }

    private func decodeDeviceSync(_ json: String) throws -> DeviceSyncSchema {
        try JSONDecoder().decode(DeviceSyncSchema.self, from: Data(json.utf8))
    }

    // MARK: - New SaveSchema fields present

    @Test func decodesNewFieldsWhenPresent() throws {
        let save = try decode(saveFields: """
        "slot": "0",
        "content_hash": "abc123",
        "origin_device_id": "device-abc",
        "device_syncs": [
          { "device_id": "device-abc", "is_current": true }
        ]
        """)
        #expect(save.slot == "0")
        #expect(save.contentHash == "abc123")
        #expect(save.originDeviceId == "device-abc")
        #expect(save.deviceSyncs?.count == 1)
        #expect(save.deviceSyncs?.first?.deviceId == "device-abc")
    }

    // MARK: - New SaveSchema fields missing entirely

    @Test func newFieldsDefaultToNilWhenMissing() throws {
        let save = try decode(saveFields: "")
        #expect(save.slot == nil)
        #expect(save.contentHash == nil)
        #expect(save.originDeviceId == nil)
        #expect(save.deviceSyncs == nil)
    }

    // MARK: - New SaveSchema fields explicitly null

    @Test func newFieldsDecodeAsNilWhenExplicitlyNull() throws {
        let save = try decode(saveFields: """
        "slot": null,
        "content_hash": null,
        "origin_device_id": null,
        "device_syncs": null
        """)
        #expect(save.slot == nil)
        #expect(save.contentHash == nil)
        #expect(save.originDeviceId == nil)
        #expect(save.deviceSyncs == nil)
    }

    @Test func emptyDeviceSyncsArrayDecodesAsEmptyNotNil() throws {
        let save = try decode(saveFields: #""device_syncs": []"#)
        #expect(save.deviceSyncs?.isEmpty == true)
    }

    // MARK: - Flexible date formats on a required date field (created_at)

    @Test func createdAtParsesWithFractionalSecondsAndZ() throws {
        let save = try decode(createdAt: "2025-03-20T08:15:30.123Z")
        let expected = ISO8601DateFormatter().date(from: "2025-03-20T08:15:30Z")!
        #expect(abs(save.createdAt.timeIntervalSince(expected)) < 1)
    }

    @Test func createdAtParsesWithoutFractionalSecondsWithZ() throws {
        let save = try decode(createdAt: "2025-03-20T08:15:30Z")
        let expected = ISO8601DateFormatter().date(from: "2025-03-20T08:15:30Z")!
        #expect(save.createdAt == expected)
    }

    @Test func createdAtParsesWithoutTimezoneOffset() throws {
        // No trailing "Z"/offset, the naive-datetime fallback in decodeFlexibleDate.
        let save = try decode(createdAt: "2025-03-20T08:15:30")
        #expect(Calendar(identifier: .gregorian).component(.month, from: save.createdAt) == 3)
    }

    @Test func createdAtParsesWithoutTimezoneOffsetAndFractionalSeconds() throws {
        let save = try decode(createdAt: "2025-03-20T08:15:30.500")
        #expect(Calendar(identifier: .gregorian).component(.month, from: save.createdAt) == 3)
    }

    @Test func unparseableCreatedAtThrowsOnRequiredField() throws {
        #expect(throws: (any Error).self) {
            try decode(createdAt: "not-a-date")
        }
    }

    // MARK: - DeviceSyncSchema

    @Test func deviceSyncDecodesAllFieldsWhenPresent() throws {
        let deviceSync = try decodeDeviceSync("""
        {
          "device_id": "device-abc",
          "device_name": "iPhone 17 Pro",
          "last_synced_at": "2025-01-15T10:30:00Z",
          "is_untracked": true,
          "is_current": true
        }
        """)
        #expect(deviceSync.deviceId == "device-abc")
        #expect(deviceSync.deviceName == "iPhone 17 Pro")
        #expect(deviceSync.lastSyncedAt != nil)
        #expect(deviceSync.isUntracked == true)
        #expect(deviceSync.isCurrent == true)
    }

    @Test func deviceSyncOptionalFieldsDefaultWhenMissing() throws {
        let deviceSync = try decodeDeviceSync(#"{ "device_id": "device-abc" }"#)
        #expect(deviceSync.deviceName == nil)
        #expect(deviceSync.lastSyncedAt == nil)
        #expect(deviceSync.isUntracked == false)
        #expect(deviceSync.isCurrent == false)
    }

    @Test func deviceSyncOptionalFieldsDecodeAsNilOrDefaultWhenExplicitlyNull() throws {
        let deviceSync = try decodeDeviceSync("""
        {
          "device_id": "device-abc",
          "device_name": null,
          "last_synced_at": null,
          "is_untracked": null,
          "is_current": null
        }
        """)
        #expect(deviceSync.deviceName == nil)
        #expect(deviceSync.lastSyncedAt == nil)
        #expect(deviceSync.isUntracked == false)
        #expect(deviceSync.isCurrent == false)
    }

    // decodeFlexibleDate's optional overload swallows a parse failure into nil
    // instead of throwing, unlike the non-optional overload used for created_at.
    @Test func deviceSyncUnparseableLastSyncedAtDecodesAsNilInsteadOfThrowing() throws {
        let deviceSync = try decodeDeviceSync("""
        { "device_id": "device-abc", "last_synced_at": "not-a-date" }
        """)
        #expect(deviceSync.lastSyncedAt == nil)
    }

    @Test func missingDeviceSyncsElementDoesNotCrashParent() throws {
        // One well-formed device sync alongside the save, sanity-checking the
        // array path end to end rather than the type in isolation.
        let save = try decode(saveFields: """
        "device_syncs": [
          { "device_id": "device-a", "is_current": true },
          { "device_id": "device-b", "is_untracked": true }
        ]
        """)
        #expect(save.deviceSyncs?.count == 2)
        #expect(save.deviceSyncs?[0].isCurrent == true)
        #expect(save.deviceSyncs?[1].isUntracked == true)
    }
}
