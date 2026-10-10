//
//  SFTPServiceTests.swift
//  rommTests
//
//  `SFTPService` drives an injected `SFTPClient`. These tests check that each
//  operation reaches the right client call and that progress is passed on.
//

import Foundation
import Testing
@testable import romm

@MainActor
struct SFTPServiceTests {
    private let client = FakeSFTPClient()
    private let connection = SFTPConnection(name: "Handheld", host: "192.168.1.20", port: 2222, username: "ark")

    private func makeService(password: String = "secret") -> (SFTPService, EndpointRecorder) {
        let repository = FakeSFTPRepository()
        repository.credentials = SFTPCredentials(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            authenticationType: .password,
            password: password
        )
        let recorder = EndpointRecorder()
        let service = SFTPService(repository: repository) { [client] endpoint in
            recorder.endpoints.append(endpoint)
            return client
        }
        return (service, recorder)
    }

    @Test func deleteFileRemovesThePathInsteadOfCreatingADirectory() async throws {
        let (service, _) = makeService()

        try await service.deleteFile(at: "/roms/gba/old.gba", connection: connection)

        #expect(client.removedPaths == ["/roms/gba/old.gba"])
        #expect(client.createdDirectories.isEmpty)
        #expect(client.didDisconnect)
    }

    @Test func downloadFileWritesThroughTheClientAndReportsProgress() async throws {
        client.downloadProgress = [(40, 100), (100, 100)]
        let (service, _) = makeService()
        let progress = ProgressRecorder()

        try await service.downloadFile(from: "/roms/gba/game.gba", to: "/tmp/game.gba", connection: connection) {
            progress.values.append(.init(done: $0, total: $1))
        }

        #expect(client.downloads.map(\.remote) == ["/roms/gba/game.gba"])
        #expect(client.downloads.map(\.local) == ["/tmp/game.gba"])
        await progress.waitFor(count: 2)
        #expect(progress.values == [.init(done: 40, total: 100), .init(done: 100, total: 100)])
    }

    @Test func uploadFileReportsProgressAndEndsAtFullSize() async throws {
        client.uploadProgress = [50, 100]
        let (service, _) = makeService()
        let progress = ProgressRecorder()
        let localPath = try makeLocalFile(size: 100)

        try await service.uploadFile(from: localPath, to: "/roms/gba/new.gba", connection: connection) {
            progress.values.append(.init(done: $0, total: $1))
        }

        #expect(client.uploads.map(\.remote) == ["/roms/gba/new.gba"])
        await progress.waitFor(count: 3)
        #expect(progress.values == [
            .init(done: 50, total: 100), .init(done: 100, total: 100), .init(done: 100, total: 100)
        ])
    }

    @Test func uploadErrorAfterFullProgressStillCountsAsSuccess() async throws {
        client.uploadProgress = [100]
        client.uploadError = SFTPError.uploadFailed
        let (service, _) = makeService()
        let localPath = try makeLocalFile(size: 100)

        try await service.uploadFile(from: localPath, to: "/roms/gba/new.gba", connection: connection) { _, _ in }
    }

    @Test func uploadErrorBeforeFullProgressFails() async throws {
        client.uploadProgress = [30]
        client.uploadError = SFTPError.uploadFailed
        let (service, _) = makeService()
        let localPath = try makeLocalFile(size: 100)

        await #expect(throws: SFTPError.self) {
            try await service.uploadFile(from: localPath, to: "/roms/gba/new.gba", connection: connection) { _, _ in }
        }
    }

    @Test func listDirectoryBuildsFullPathsFromTheClientItems() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        client.directoryItems = [
            SFTPClientItem(name: "gba", isDirectory: true, size: 0, modificationDate: date),
            SFTPClientItem(name: "game.gba", isDirectory: false, size: 4096, modificationDate: date)
        ]
        let (service, _) = makeService()

        let items = try await service.listDirectory(at: "/roms/", connection: connection)

        #expect(items.map(\.path) == ["/roms/gba", "/roms/game.gba"])
        #expect(items.map(\.isDirectory) == [true, false])
        #expect(items.map(\.size) == [0, 4096])
    }

    @Test func clientIsCreatedFromTheConnectionAndStoredPassword() async throws {
        let (service, recorder) = makeService(password: "hunter2")

        try await service.createDirectory(at: "/roms/new", connection: connection)

        #expect(recorder.endpoints == [SFTPEndpoint(host: "192.168.1.20", port: 2222, username: "ark", password: "hunter2")])
        #expect(client.createdDirectories == ["/roms/new"])
    }

    private func makeLocalFile(size: Int) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(count: size).write(to: url)
        return url.path
    }
}

private final class EndpointRecorder: @unchecked Sendable {
    var endpoints: [SFTPEndpoint] = []
}

@MainActor
private final class ProgressRecorder {
    struct Value: Equatable {
        let done: Int64
        let total: Int64
    }

    var values: [Value] = []

    /// The service hands progress to the main queue asynchronously, so give it
    /// a moment to drain before checking.
    func waitFor(count: Int) async {
        for _ in 0..<100 where values.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
