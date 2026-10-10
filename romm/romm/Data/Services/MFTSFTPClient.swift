import Foundation
import mft

/// `SFTPClient` on top of mft (LGPL-2.1, libssh). The only file that knows mft.
final class MFTSFTPClient: SFTPClient {
    private static let maxDirectoryItems: Int64 = 1000

    private let connection: MFTSftpConnection

    init(endpoint: SFTPEndpoint) {
        connection = MFTSftpConnection(
            hostname: endpoint.host,
            port: endpoint.port,
            username: endpoint.username,
            password: endpoint.password
        )
    }

    func connect() throws {
        do {
            try connection.connect()
        } catch {
            throw SFTPError.connectionFailed
        }
    }

    func authenticate() throws {
        do {
            try connection.authenticate()
        } catch {
            throw SFTPError.authenticationFailed
        }
    }

    func disconnect() {
        connection.disconnect()
    }

    func contentsOfDirectory(atPath path: String) throws -> [SFTPClientItem] {
        do {
            return try connection.contentsOfDirectory(atPath: path, maxItems: Self.maxDirectoryItems).map {
                SFTPClientItem(name: $0.filename, isDirectory: $0.isDirectory, size: $0.size, modificationDate: $0.mtime)
            }
        } catch {
            throw SFTPError.pathNotFound
        }
    }

    func uploadFile(atPath localPath: String, toPath remotePath: String, progress: @escaping (UInt64) -> Bool) throws {
        do {
            try connection.uploadFile(atPath: localPath, toFileAtPath: remotePath, progress: progress)
        } catch {
            throw SFTPError.uploadFailed
        }
    }

    func downloadFile(atPath remotePath: String, toPath localPath: String, progress: @escaping (UInt64, UInt64) -> Bool) throws {
        do {
            try connection.downloadFile(atPath: remotePath, toFileAtPath: localPath, progress: progress)
        } catch {
            throw SFTPError.downloadFailed
        }
    }

    func createDirectory(atPath path: String) throws {
        do {
            try connection.createDirectory(atPath: path)
        } catch {
            throw SFTPError.pathNotFound
        }
    }

    func removeFile(atPath path: String) throws {
        do {
            try connection.removeFile(atPath: path)
        } catch {
            throw SFTPError.pathNotFound
        }
    }
}
