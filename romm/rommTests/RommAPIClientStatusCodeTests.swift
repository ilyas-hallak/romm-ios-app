//
//  RommAPIClientStatusCodeTests.swift
//  rommTests
//
//  409 has to become `APIClientError.conflict` on both codepaths a save
//  upload can take: the plain JSON path (`makeRequest`) and the multipart
//  path (`multipartRequest`). Neighbouring status codes must not drift into
//  `.conflict`, and 409 must not fall through to the broader 400...499 case.
//

import Foundation
import Testing
@testable import romm

/// Counts calls from a closure that outlives the statement it was written in.
private final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func mark() { count += 1 }
}

struct RommAPIClientStatusCodeTests {

    /// Counts only the posts of `client`, other suites post `.sessionExpired` concurrently.
    private func countSessionExpiredPosts(from client: RommAPIClient, during body: () async -> Void) async -> Int {
        let posts = CallCounter()
        let observer = NotificationCenter.default.addObserver(forName: .sessionExpired, object: client, queue: nil) { _ in posts.mark() }
        defer { NotificationCenter.default.removeObserver(observer) }
        await body()
        return posts.count
    }

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

    private func uploadOnce(client: RommAPIClient) async throws {
        _ = try await client.uploadSave(
            romId: 1,
            emulator: nil,
            slot: nil,
            deviceId: "device-abc",
            sessionId: nil,
            autocleanup: nil,
            overwrite: nil,
            fileName: "game.srm",
            fileData: Data([0x01]),
            screenshotData: nil
        )
    }

    // MARK: - JSON path (makeRequest), via confirmSaveDownloaded

    @Test func jsonPath409BecomesConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 409, body: Data("slot moved".utf8)),
            forHost: host
        )
        do {
            _ = try await client.confirmSaveDownloaded(id: 1, deviceId: "device-abc")
            Issue.record("Expected APIClientError.conflict")
        } catch APIClientError.conflict {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func jsonPath400StaysInvalidResponseNotConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 400, body: Data("bad request".utf8)),
            forHost: host
        )
        do {
            _ = try await client.confirmSaveDownloaded(id: 1, deviceId: "device-abc")
            Issue.record("Expected APIClientError.invalidResponse")
        } catch APIClientError.invalidResponse(let code, _) {
            #expect(code == 400)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func jsonPath404StaysInvalidResponseNotConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 404, body: Data("not found".utf8)),
            forHost: host
        )
        do {
            _ = try await client.confirmSaveDownloaded(id: 1, deviceId: "device-abc")
            Issue.record("Expected APIClientError.invalidResponse")
        } catch APIClientError.invalidResponse(let code, _) {
            #expect(code == 404)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func jsonPath500StaysInvalidResponseNotConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 500, body: Data("boom".utf8)),
            forHost: host
        )
        do {
            _ = try await client.confirmSaveDownloaded(id: 1, deviceId: "device-abc")
            Issue.record("Expected APIClientError.invalidResponse")
        } catch APIClientError.invalidResponse(let code, _) {
            #expect(code == 500)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func jsonPath401ThrowsAuthenticationRequired() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 401, body: Data("invalid credentials".utf8)),
            forHost: host
        )
        let posts = await countSessionExpiredPosts(from: client) {
            do {
                _ = try await client.confirmSaveDownloaded(id: 1, deviceId: "device-abc")
                Issue.record("Expected APIClientError.authenticationRequired")
            } catch APIClientError.authenticationRequired {
                // expected
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
        #expect(posts == 1)
    }

    /// RomM 5.3's CSRF check can reject a request with 403 even though the bearer
    /// token is still valid, so 403 must stay a regular error and never log the
    /// user out the way 401 does.
    @Test func jsonPath403StaysInvalidResponseNotAuthRequired() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 403, body: Data("CSRF token verification failed".utf8)),
            forHost: host
        )
        let posts = await countSessionExpiredPosts(from: client) {
            do {
                _ = try await client.confirmSaveDownloaded(id: 1, deviceId: "device-abc")
                Issue.record("Expected APIClientError.invalidResponse")
            } catch APIClientError.invalidResponse(let code, _) {
                #expect(code == 403)
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
        #expect(posts == 0)
    }

    @Test func jsonPathSuccessWithEmptyBodyDoesNotThrow() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Data("{}".utf8)),
            forHost: host
        )
        // completeSyncSession decodes its response into a zero-property struct,
        // so an empty JSON object is the "nothing here" case the API allows.
        try await client.completeSyncSession(sessionId: "s1", operationsCompleted: 1, operationsFailed: 0)
    }

    // MARK: - Multipart path (multipartRequest), via uploadSave

    @Test func multipartPath409BecomesConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 409, body: Data("slot moved".utf8)),
            forHost: host
        )
        do {
            try await uploadOnce(client: client)
            Issue.record("Expected APIClientError.conflict")
        } catch APIClientError.conflict {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func multipartPath400StaysInvalidResponseNotConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 400, body: Data("bad request".utf8)),
            forHost: host
        )
        do {
            try await uploadOnce(client: client)
            Issue.record("Expected APIClientError.invalidResponse")
        } catch APIClientError.invalidResponse(let code, _) {
            #expect(code == 400)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func multipartPath404StaysInvalidResponseNotConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 404, body: Data("not found".utf8)),
            forHost: host
        )
        do {
            try await uploadOnce(client: client)
            Issue.record("Expected APIClientError.invalidResponse")
        } catch APIClientError.invalidResponse(let code, _) {
            #expect(code == 404)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func multipartPath500StaysInvalidResponseNotConflict() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 500, body: Data("boom".utf8)),
            forHost: host
        )
        do {
            try await uploadOnce(client: client)
            Issue.record("Expected APIClientError.invalidResponse")
        } catch APIClientError.invalidResponse(let code, _) {
            #expect(code == 500)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func multipartPath401ThrowsAuthenticationRequired() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 401, body: Data("invalid credentials".utf8)),
            forHost: host
        )
        let posts = await countSessionExpiredPosts(from: client) {
            do {
                try await uploadOnce(client: client)
                Issue.record("Expected APIClientError.authenticationRequired")
            } catch APIClientError.authenticationRequired {
                // expected
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
        #expect(posts == 1)
    }

    @Test func multipartPath403StaysInvalidResponseNotAuthRequired() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 403, body: Data("CSRF token verification failed".utf8)),
            forHost: host
        )
        let posts = await countSessionExpiredPosts(from: client) {
            do {
                try await uploadOnce(client: client)
                Issue.record("Expected APIClientError.invalidResponse")
            } catch APIClientError.invalidResponse(let code, _) {
                #expect(code == 403)
            } catch {
                Issue.record("Wrong error type: \(error)")
            }
        }
        #expect(posts == 0)
    }

    @Test func multipartPathSuccessDoesNotThrow() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 200, body: Self.minimalSaveResponse),
            forHost: host
        )
        _ = try await uploadOnce(client: client)
    }

    // MARK: - Manual PDF path (getManualPDFData, its own request builder)

    @Test func manualPDFPath401ThrowsAuthenticationRequired() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 401, body: Data("invalid credentials".utf8)),
            forHost: host
        )
        do {
            _ = try await client.getManualPDFData(manualURL: "https://\(host)/manual.pdf")
            Issue.record("Expected APIClientError.authenticationRequired")
        } catch APIClientError.authenticationRequired {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func manualPDFPath403StaysInvalidResponse() async throws {
        let (client, host) = makeStubbedClient()
        URLProtocolStubRegistry.shared.setResponse(
            StubbedResponse(statusCode: 403, body: Data("CSRF token verification failed".utf8)),
            forHost: host
        )
        do {
            _ = try await client.getManualPDFData(manualURL: "https://\(host)/manual.pdf")
            Issue.record("Expected APIClientError.invalidResponse")
        } catch APIClientError.invalidResponse(let code, _) {
            #expect(code == 403)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}
