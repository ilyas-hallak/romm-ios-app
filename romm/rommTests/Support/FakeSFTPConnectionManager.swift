//
//  FakeSFTPConnectionManager.swift
//  rommTests
//
//  Stand-in for `PSFTPConnectionManager`, so the SFTP use cases can be driven
//  without the real singleton. Records what it was asked to do.
//

import Foundation
@testable import romm

final class FakeSFTPConnectionManager: PSFTPConnectionManager, @unchecked Sendable {
    var connectionStatus: ConnectionStatus = .connected
    var testConnectionResult: Result<Bool, Error> = .success(true)
    var directoryItems: [SFTPDirectoryItem] = []
    var listDirectoryError: Error?
    var createDirectoryError: Error?
    var uploadError: Error?
    var downloadError: Error?
    var deleteFileError: Error?

    private(set) var checkedStatusConnections: [UUID] = []
    private(set) var checkedAllStatusesConnections: [UUID] = []
    private(set) var testedCredentialsConnections: [UUID] = []
    private(set) var listedDirectoryPaths: [String] = []
    private(set) var uploadedFiles: [(local: String, remote: String)] = []
    private(set) var downloadedFiles: [(remote: String, local: String)] = []
    private(set) var createdDirectoryPaths: [String] = []
    private(set) var deletedFilePaths: [String] = []
    private(set) var clearedCacheCallCount = 0
    private(set) var clearedCacheConnections: [UUID] = []

    func checkConnectionStatus(for connection: SFTPConnection, forceRefresh: Bool) async -> ConnectionStatus {
        checkedStatusConnections.append(connection.id)
        return connectionStatus
    }

    func checkAllConnectionStatuses(for connections: [SFTPConnection], forceRefresh: Bool) async {
        checkedAllStatusesConnections.append(contentsOf: connections.map(\.id))
    }

    func testConnection(_ connection: SFTPConnection, credentials: SFTPCredentials) async throws -> Bool {
        testedCredentialsConnections.append(connection.id)
        return try testConnectionResult.get()
    }

    func listDirectory(at path: String, connection: SFTPConnection) async throws -> [SFTPDirectoryItem] {
        listedDirectoryPaths.append(path)
        if let listDirectoryError { throw listDirectoryError }
        return directoryItems
    }

    func uploadFile(from localPath: String, to remotePath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws {
        uploadedFiles.append((localPath, remotePath))
        if let uploadError { throw uploadError }
    }

    func downloadFile(from remotePath: String, to localPath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws {
        downloadedFiles.append((remotePath, localPath))
        if let downloadError { throw downloadError }
    }

    func createDirectory(at path: String, connection: SFTPConnection) async throws {
        createdDirectoryPaths.append(path)
        if let createDirectoryError { throw createDirectoryError }
    }

    func deleteFile(at path: String, connection: SFTPConnection) async throws {
        deletedFilePaths.append(path)
        if let deleteFileError { throw deleteFileError }
    }

    func clearCache() async {
        clearedCacheCallCount += 1
    }

    func clearCache(for connection: SFTPConnection) async {
        clearedCacheConnections.append(connection.id)
    }
}
