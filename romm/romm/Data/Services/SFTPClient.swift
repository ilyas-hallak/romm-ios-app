import Foundation

/// The SFTP operations the app needs, independent of the library behind them.
/// Calls block, so run them off the main thread.
protocol SFTPClient: AnyObject {
    func connect() throws
    func authenticate() throws
    func disconnect()
    func contentsOfDirectory(atPath path: String) throws -> [SFTPClientItem]
    /// `progress` gets the bytes sent so far and returns false to stop.
    func uploadFile(atPath localPath: String, toPath remotePath: String, progress: @escaping (UInt64) -> Bool) throws
    /// `progress` gets the bytes received so far and the file size and returns false to stop.
    func downloadFile(atPath remotePath: String, toPath localPath: String, progress: @escaping (UInt64, UInt64) -> Bool) throws
    func createDirectory(atPath path: String) throws
    func removeFile(atPath path: String) throws
}

struct SFTPClientItem: Equatable {
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let modificationDate: Date
}

struct SFTPEndpoint: Equatable {
    let host: String
    let port: Int
    let username: String
    let password: String
}

typealias SFTPClientFactory = (SFTPEndpoint) -> SFTPClient
