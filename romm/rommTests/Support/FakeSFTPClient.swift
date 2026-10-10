//
//  FakeSFTPClient.swift
//  rommTests
//
//  Stand-ins for `SFTPClient` and `PSFTPRepository`, so `SFTPService` can be
//  driven without a server. The client records what it was asked to do and
//  replays scripted progress values.
//

import Foundation
@testable import romm

final class FakeSFTPClient: SFTPClient, @unchecked Sendable {
    var directoryItems: [SFTPClientItem] = []
    var uploadProgress: [UInt64] = []
    var downloadProgress: [(UInt64, UInt64)] = []
    var uploadError: Error?

    private(set) var removedPaths: [String] = []
    private(set) var createdDirectories: [String] = []
    private(set) var uploads: [(local: String, remote: String)] = []
    private(set) var downloads: [(remote: String, local: String)] = []
    private(set) var didDisconnect = false

    func connect() throws {}
    func authenticate() throws {}
    func disconnect() { didDisconnect = true }

    func contentsOfDirectory(atPath path: String) throws -> [SFTPClientItem] { directoryItems }

    func uploadFile(atPath localPath: String, toPath remotePath: String, progress: @escaping (UInt64) -> Bool) throws {
        uploads.append((localPath, remotePath))
        for sent in uploadProgress where !progress(sent) { break }
        if let uploadError { throw uploadError }
    }

    func downloadFile(atPath remotePath: String, toPath localPath: String, progress: @escaping (UInt64, UInt64) -> Bool) throws {
        downloads.append((remotePath, localPath))
        for (received, total) in downloadProgress where !progress(received, total) { break }
    }

    func createDirectory(atPath path: String) throws { createdDirectories.append(path) }
    func removeFile(atPath path: String) throws { removedPaths.append(path) }
}

final class FakeSFTPRepository: PSFTPRepository, @unchecked Sendable {
    var credentials: SFTPCredentials?

    func getAllConnections() -> [SFTPConnection] { [] }
    func getConnection(by id: UUID) -> SFTPConnection? { nil }
    func saveConnection(_ connection: SFTPConnection, credentials: SFTPCredentials) throws {}
    func deleteConnection(_ connection: SFTPConnection) throws {}
    func setDefaultConnection(_ connection: SFTPConnection) throws {}
    func getDefaultConnection() -> SFTPConnection? { nil }
    func getCredentials(for connectionId: UUID) -> SFTPCredentials? { credentials }
    func getFavoriteDirectories(for connectionId: UUID) -> [String] { [] }
    func addFavoriteDirectory(_ path: String, for connectionId: UUID) throws {}
    func removeFavoriteDirectory(_ path: String, for connectionId: UUID) throws {}
}
