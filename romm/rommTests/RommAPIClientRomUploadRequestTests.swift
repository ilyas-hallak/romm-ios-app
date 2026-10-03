//
//  RommAPIClientRomUploadRequestTests.swift
//  rommTests
//
//  HTTP-level tests for the chunked ROM upload endpoints: headers, method,
//  path and the typed duplicate-file error, read from the raw request the
//  stub intercepted.
//

import Foundation
import Testing
@testable import romm

struct RommAPIClientRomUploadRequestTests {

    // MARK: - startRomUpload

    @Test func startRomUploadSendsTheUploadHeaders() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 201, body: Data(#"{"upload_id":"abc-123"}"#.utf8)),
            forHost: host
        )

        let uploadId = try await client.startRomUpload(
            platformId: 3,
            fileName: "Pokemon Red.gb",
            fileSize: 1_048_576,
            totalChunks: 1
        )

        #expect(uploadId == "abc-123")
        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url.path == "/api/roms/upload/start")
        #expect(recorded.headers["x-upload-platform"] == "3")
        #expect(recorded.headers["x-upload-total-size"] == "1048576")
        #expect(recorded.headers["x-upload-total-chunks"] == "1")
    }

    @Test func startRomUploadPercentEncodesTheFilenameHeaderButNotTheJSONBody() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 201, body: Data(#"{"upload_id":"abc-123"}"#.utf8)),
            forHost: host
        )

        _ = try await client.startRomUpload(
            platformId: 1,
            fileName: "Pokémon Blue.gb",
            fileSize: 10,
            totalChunks: 1
        )

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.headers["x-upload-filename"] == "Pok%C3%A9mon%20Blue.gb")
        let json = try #require(recorded.jsonBody)
        #expect(json["filename"] as? String == "Pokémon Blue.gb")
    }

    @Test func startRomUploadMapsAlreadyExistsToDuplicateFileName() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 400, body: Data(#"{"detail":"File Pokemon Red.gb already exists"}"#.utf8)),
            forHost: host
        )

        do {
            _ = try await client.startRomUpload(platformId: 1, fileName: "Pokemon Red.gb", fileSize: 10, totalChunks: 1)
            Issue.record("Expected RomUploadError.duplicateFileName to be thrown")
        } catch let error as RomUploadError {
            guard case .duplicateFileName = error else {
                Issue.record("Expected .duplicateFileName, got \(error)")
                return
            }
        }
    }

    // MARK: - uploadRomChunk

    @Test func uploadRomChunkSendsTheChunkIndexAndRawBytes() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Data(#"{"received":1,"total":2}"#.utf8)),
            forHost: host
        )
        let chunkURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0x01, 0x02, 0x03]).write(to: chunkURL)
        defer { try? FileManager.default.removeItem(at: chunkURL) }

        try await client.uploadRomChunk(uploadId: "abc-123", index: 1, fileURL: chunkURL, progressHandler: nil)

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.httpMethod == "PUT")
        #expect(recorded.url.path == "/api/roms/upload/abc-123")
        #expect(recorded.headers["x-chunk-index"] == "1")
        #expect(recorded.headers["Content-Type"] == "application/octet-stream")
        #expect(recorded.body == Data([0x01, 0x02, 0x03]))
    }

    // MARK: - completeRomUpload / cancelRomUpload

    @Test func completeRomUploadHitsTheCompletePath() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(StubbedResponse(statusCode: 201), forHost: host)

        try await client.completeRomUpload(uploadId: "abc-123")

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url.path == "/api/roms/upload/abc-123/complete")
    }

    @Test func cancelRomUploadHitsTheCancelPathAndSwallowsErrors() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(StubbedResponse(statusCode: 404), forHost: host)

        // Best-effort: a 404 (session already gone) must not throw.
        try await client.cancelRomUpload(uploadId: "abc-123")

        let recorded = try #require(URLProtocolStubRegistry.shared.recordedRequest(forHost: host))
        #expect(recorded.httpMethod == "POST")
        #expect(recorded.url.path == "/api/roms/upload/abc-123/cancel")
    }
}
