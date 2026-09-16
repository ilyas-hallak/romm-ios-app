//
//  RommAPIClientSaveSyncRequestTests.swift
//  rommTests
//
//  HTTP-level tests for the manual save-sync endpoints: what RommAPIClient
//  actually puts on the wire for upload, download confirmation and session
//  completion. Every assertion reads the raw request the stub intercepted,
//  not a value decoded back through the same model.
//

import Foundation
import Testing
@testable import romm

struct RommAPIClientSaveSyncRequestTests {

    // A save response just complete enough for SaveSchema to decode; only its
    // shape matters here, not its content.
    private static let minimalSaveResponse = Data("""
    {
      "id": 99,
      "rom_id": 1,
      "user_id": 1,
      "file_name": "game.srm",
      "file_name_no_tags": "game",
      "file_name_no_ext": "game",
      "file_extension": "srm",
      "file_path": "saves/game.srm",
      "file_size_bytes": 10,
      "full_path": "saves/game.srm",
      "download_path": "/api/saves/99/content",
      "missing_from_fs": false,
      "created_at": "2025-01-15T10:30:00Z",
      "updated_at": "2025-01-15T10:30:00Z"
    }
    """.utf8)

    // MARK: - uploadSave: query construction

    @Test func uploadSaveQueryContainsAutocleanupDeviceAndSession() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )

        _ = try await client.uploadSave(
            romId: 1,
            emulator: "mgba",
            slot: "0",
            deviceId: "device-abc",
            sessionId: "session-xyz",
            autocleanup: true,
            overwrite: nil,
            fileName: "game.srm",
            fileData: Data([0x01, 0x02]),
            screenshotData: nil
        )

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url.path == "/api/saves")
        let query = recorded.queryItems
        #expect(query.contains(URLQueryItem(name: "autocleanup", value: "true")))
        #expect(query.contains(URLQueryItem(name: "device_id", value: "device-abc")))
        #expect(query.contains(URLQueryItem(name: "session_id", value: "session-xyz")))
    }

    @Test func uploadSaveOmitsSessionIdWhenNil() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )

        _ = try await client.uploadSave(
            romId: 1,
            emulator: "mgba",
            slot: "0",
            deviceId: "device-abc",
            sessionId: nil,
            autocleanup: true,
            overwrite: nil,
            fileName: "game.srm",
            fileData: Data([0x01]),
            screenshotData: nil
        )

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(!recorded.queryItems.contains { $0.name == "session_id" })
        #expect(!recorded.url.absoluteString.contains("session_id"))
    }

    @Test func uploadSaveSerializesAutocleanupFalse() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )

        _ = try await client.uploadSave(
            romId: 1,
            emulator: nil,
            slot: nil,
            deviceId: nil,
            sessionId: nil,
            autocleanup: false,
            overwrite: nil,
            fileName: "game.srm",
            fileData: Data([0x01]),
            screenshotData: nil
        )

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.queryItems.contains(URLQueryItem(name: "autocleanup", value: "false")))
    }

    @Test func uploadSaveSerializesOverwriteTrue() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )

        _ = try await client.uploadSave(
            romId: 1,
            emulator: nil,
            slot: "battery",
            deviceId: "device-abc",
            sessionId: nil,
            autocleanup: true,
            overwrite: true,
            fileName: "battery.sav",
            fileData: Data([0x01]),
            screenshotData: nil
        )

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.queryItems.contains(URLQueryItem(name: "overwrite", value: "true")))
    }

    /// Left off entirely rather than sent as false, so the server's own
    /// default stays the conflict guard for every caller that has not
    /// established that it wins.
    @Test func uploadSaveOmitsOverwriteWhenNil() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )

        _ = try await client.uploadSave(
            romId: 1,
            emulator: nil,
            slot: "battery",
            deviceId: "device-abc",
            sessionId: nil,
            autocleanup: true,
            overwrite: nil,
            fileName: "battery.sav",
            fileData: Data([0x01]),
            screenshotData: nil
        )

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(!recorded.queryItems.contains { $0.name == "overwrite" })
    }

    // MARK: - confirmSaveDownloaded

    @Test func confirmSaveDownloadedHitsTheRightPathAndMethod() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )

        _ = try await client.confirmSaveDownloaded(id: 42, deviceId: "device-abc")

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url.path == "/api/saves/42/downloaded")
    }

    @Test func confirmSaveDownloadedBodyCarriesRawDeviceIdKey() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )

        _ = try await client.confirmSaveDownloaded(id: 42, deviceId: "device-abc")

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        let json = try #require(recorded.jsonBody)
        #expect(json["device_id"] as? String == "device-abc")
        #expect(json.count == 1)
    }

    // MARK: - completeSyncSession

    @Test func completeSyncSessionHitsTheRightPathAndMethod() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Data("{}".utf8)),
            forHost: host
        )

        try await client.completeSyncSession(sessionId: "session-xyz", operationsCompleted: 3, operationsFailed: 1)

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url.path == "/api/sync/sessions/session-xyz/complete")
    }

    @Test func completeSyncSessionBodyCarriesRawOperationCounts() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Data("{}".utf8)),
            forHost: host
        )

        try await client.completeSyncSession(sessionId: "session-xyz", operationsCompleted: 3, operationsFailed: 1)

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        let json = try #require(recorded.jsonBody)
        #expect(json["operations_completed"] as? Int == 3)
        #expect(json["operations_failed"] as? Int == 1)
    }

    @Test func completeSyncSessionAllowsBothCountersAtZero() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Data("{}".utf8)),
            forHost: host
        )

        try await client.completeSyncSession(sessionId: "session-xyz", operationsCompleted: 0, operationsFailed: 0)

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        let json = try #require(recorded.jsonBody)
        #expect(json["operations_completed"] as? Int == 0)
        #expect(json["operations_failed"] as? Int == 0)
    }
}
