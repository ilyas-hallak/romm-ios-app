//
//  SFTPUseCasesTests.swift
//  rommTests
//
//  The use cases that wrap `SFTPConnectionManager` now depend on
//  `PSFTPConnectionManager`, so they can be driven with a fake instead of the
//  real singleton.
//

import Foundation
import Testing
@testable import romm

@MainActor
struct SFTPUseCasesTests {
    private let connection = SFTPConnection(name: "Handheld", host: "192.168.1.20", port: 2222, username: "ark")

    @Test func listDirectoryUseCaseReturnsWhatTheManagerLists() async throws {
        let manager = FakeSFTPConnectionManager()
        manager.directoryItems = [
            SFTPDirectoryItem(name: "game.gba", path: "/roms/game.gba", isDirectory: false, size: 4096, modificationDate: nil)
        ]
        let useCase = ListDirectoryUseCase(connectionManager: manager)

        let items = try await useCase.execute(at: "/roms", connection: connection)

        #expect(manager.listedDirectoryPaths == ["/roms"])
        #expect(items.map(\.name) == ["game.gba"])
    }

    @Test func uploadFileUseCaseDelegatesToTheManager() async throws {
        let manager = FakeSFTPConnectionManager()
        let useCase = UploadFileUseCase(connectionManager: manager)

        try await useCase.execute(from: "/tmp/game.gba", to: "/roms/game.gba", connection: connection) { _, _ in }

        #expect(manager.uploadedFiles.map(\.local) == ["/tmp/game.gba"])
        #expect(manager.uploadedFiles.map(\.remote) == ["/roms/game.gba"])
    }

    @Test func createSFTPDirectoryUseCaseDelegatesToTheManager() async throws {
        let manager = FakeSFTPConnectionManager()
        let useCase = CreateSFTPDirectoryUseCase(connectionManager: manager)

        try await useCase.execute(at: "/roms/new", connection: connection)

        #expect(manager.createdDirectoryPaths == ["/roms/new"])
    }

    @Test func checkConnectionStatusUseCaseReturnsWhatTheManagerReports() async throws {
        let manager = FakeSFTPConnectionManager()
        manager.connectionStatus = .error
        let useCase = CheckConnectionStatusUseCase(connectionManager: manager)

        let status = await useCase.execute(for: connection)

        #expect(manager.checkedStatusConnections == [connection.id])
        #expect(status == .error)
    }

    @Test func clearConnectionCacheUseCaseDelegatesToTheManager() async throws {
        let manager = FakeSFTPConnectionManager()
        let useCase = ClearConnectionCacheUseCase(connectionManager: manager)

        await useCase.execute()
        await useCase.execute(for: connection)

        #expect(manager.clearedCacheCallCount == 1)
        #expect(manager.clearedCacheConnections == [connection.id])
    }

    @Test func testConnectionUseCaseReportsFailureFromTheManagerWithoutThrowing() async throws {
        let manager = FakeSFTPConnectionManager()
        manager.testConnectionResult = .failure(SFTPError.authenticationFailed)
        let useCase = TestConnectionUseCase(connectionManager: manager)
        let credentials = SFTPCredentials(host: connection.host, port: connection.port, username: connection.username, authenticationType: .password, password: "secret")

        let isConnected = await useCase.executeWithCredentials(connection, credentials: credentials)

        #expect(manager.testedCredentialsConnections == [connection.id])
        #expect(isConnected == false)
    }
}
