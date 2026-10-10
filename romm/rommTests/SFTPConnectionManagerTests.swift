//
//  SFTPConnectionManagerTests.swift
//  rommTests
//
//  `SFTPConnectionManager` is a singleton, so this drives the one it exposes
//  through `configure(with:)` rather than creating a fresh instance. Safe only
//  because this is the one test touching `.shared`; a second one would need to
//  serialize or reset the configured service to avoid leaking state.
//

import Foundation
import Testing
@testable import romm

@MainActor
struct SFTPConnectionManagerTests {
    @Test func deleteFileDelegatesToTheConfiguredService() async throws {
        let client = FakeSFTPClient()
        let repository = FakeSFTPRepository()
        let connection = SFTPConnection(name: "Handheld", host: "192.168.1.20", port: 2222, username: "ark")
        repository.credentials = SFTPCredentials(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            authenticationType: .password,
            password: "secret"
        )
        let service = SFTPService(repository: repository) { _ in client }

        let manager = SFTPConnectionManager.shared
        manager.configure(with: service)

        try await manager.deleteFile(at: "/roms/gba/old.gba", connection: connection)

        #expect(client.removedPaths == ["/roms/gba/old.gba"])
    }
}
