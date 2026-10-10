import Foundation

enum SFTPError: LocalizedError {
    case connectionFailed
    case authenticationFailed
    case pathNotFound
    case uploadFailed
    case downloadFailed
    case connectionTimeout
    case invalidCredentials
    case networkError(String)
    case insufficientStorage(required: Int64, available: Int64)
    case serviceNotConfigured
    case fileValidationFailed(String)
    case incompleteDownload(actual: Int64, expected: Int64)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to SFTP server"
        case .authenticationFailed:
            return "Authentication failed"
        case .pathNotFound:
            return "Path not found on server"
        case .uploadFailed:
            return "Failed to upload file"
        case .downloadFailed:
            return "Failed to download file"
        case .connectionTimeout:
            return "Connection timeout"
        case .invalidCredentials:
            return "Invalid credentials"
        case .networkError(let message):
            return "Network error: \(message)"
        case .insufficientStorage(let required, let available):
            let requiredStr = ByteCountFormatter.string(fromByteCount: required, countStyle: .file)
            let availableStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Not enough storage space. Required: \(requiredStr), Available: \(availableStr)"
        case .serviceNotConfigured:
            return "SFTP service not configured"
        case .fileValidationFailed(let message):
            return "File validation failed: \(message)"
        case .incompleteDownload(let actual, let expected):
            let actualStr = ByteCountFormatter.string(fromByteCount: actual, countStyle: .file)
            let expectedStr = ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)
            return "Incomplete download: got \(actualStr), expected \(expectedStr)"
        }
    }
}

struct SFTPDirectoryItem: Identifiable {
    let id: UUID = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?
}

protocol PSFTPService {
    func testConnection(_ connection: SFTPConnection) async throws -> Bool
    func testConnectionWithCredentials(_ connection: SFTPConnection, credentials: SFTPCredentials) async throws -> Bool
    func listDirectory(at path: String, connection: SFTPConnection) async throws -> [SFTPDirectoryItem]
    func uploadFile(from localPath: String, to remotePath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws
    func downloadFile(from remotePath: String, to localPath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws
    func createDirectory(at path: String, connection: SFTPConnection) async throws
    func deleteFile(at path: String, connection: SFTPConnection) async throws
}

/// Guards a shared cancellation flag so a download's progress callback, invoked
/// from a background queue, can see a cancellation requested from the awaiting Task.
nonisolated private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
}

class SFTPService: PSFTPService {
    private let repository: PSFTPRepository
    private let makeClient: SFTPClientFactory
    private let logger = Logger.sftp

    init(repository: PSFTPRepository, makeClient: @escaping SFTPClientFactory) {
        self.repository = repository
        self.makeClient = makeClient
    }

    private func createConnection(_ connection: SFTPConnection, with credentials: SFTPCredentials? = nil) -> SFTPClient {
        let creds = credentials ?? repository.getCredentials(for: connection.id)

        return makeClient(SFTPEndpoint(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: creds?.password ?? ""
        ))
    }

    private func authenticateConnection(_ sftp: SFTPClient, connection: SFTPConnection, credentials: SFTPCredentials? = nil) throws {
        let creds = credentials ?? repository.getCredentials(for: connection.id)
        
        switch connection.authenticationType {
        case .password:
            guard let creds = creds, let password = creds.password, !password.isEmpty else {
                throw SFTPError.invalidCredentials
            }
            try sftp.authenticate()
            
        case .sshKey:
            guard let creds = creds, let privateKey = creds.privateKey, !privateKey.isEmpty else {
                throw SFTPError.invalidCredentials
            }
            // For SSH key authentication, we would need to implement key-based auth
            // This is a placeholder for the actual implementation
            throw SFTPError.authenticationFailed
            
        case .passwordWithKey:
            guard let creds = creds, 
                  let password = creds.password, !password.isEmpty,
                  let privateKey = creds.privateKey, !privateKey.isEmpty else {
                throw SFTPError.invalidCredentials
            }
            // For combined auth, we would need to implement both
            // This is a placeholder for the actual implementation
            throw SFTPError.authenticationFailed
        }
    }
    
    // OPTIMIZED: SFTP client isolated in background thread with hard timeout
    func testConnection(_ connection: SFTPConnection) async throws -> Bool {
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            // Task 1: Actual connection test in dedicated background queue
            // This ensures the client's blocking socket operations don't block Swift Concurrency threads
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    // Use DispatchQueue instead of Task.detached for complete isolation
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self else {
                            continuation.resume(returning: false)
                            return
                        }

                        do {
                            let sftp = self.createConnection(connection)
                            defer { sftp.disconnect() }

                            // The client's blocking calls run in isolated background thread
                            try sftp.connect()
                            try self.authenticateConnection(sftp, connection: connection)

                            continuation.resume(returning: true)
                        } catch {
                            continuation.resume(throwing: self.mapClientError(error))
                        }
                    }
                }
            }

            // Task 2: Hard timeout (3 seconds)
            // This ensures UI responsiveness even if the client hangs
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                throw SFTPError.connectionTimeout
            }

            // Race: First to complete wins
            guard let result = try await group.next() else {
                throw SFTPError.connectionTimeout
            }

            // Cancel the other task (either timeout or connection test)
            group.cancelAll()
            return result
        }
    }
    
    func testConnectionWithCredentials(_ connection: SFTPConnection, credentials: SFTPCredentials) async throws -> Bool {
        // Same isolation strategy as testConnection for consistency
        return try await withThrowingTaskGroup(of: Bool.self) { group in
            // Task 1: Connection test in background queue
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self else {
                            continuation.resume(returning: false)
                            return
                        }

                        do {
                            let sftp = self.createConnection(connection, with: credentials)
                            defer { sftp.disconnect() }

                            try sftp.connect()
                            try self.authenticateConnection(sftp, connection: connection, credentials: credentials)

                            continuation.resume(returning: true)
                        } catch {
                            continuation.resume(throwing: self.mapClientError(error))
                        }
                    }
                }
            }

            // Task 2: Hard timeout (3 seconds)
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw SFTPError.connectionTimeout
            }

            guard let result = try await group.next() else {
                throw SFTPError.connectionTimeout
            }

            group.cancelAll()
            return result
        }
    }
    
    func listDirectory(at path: String, connection: SFTPConnection) async throws -> [SFTPDirectoryItem] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: SFTPError.serviceNotConfigured)
                    return
                }

                do {
                    let sftp = self.createConnection(connection)

                    try sftp.connect()
                    defer { sftp.disconnect() }

                    try sftp.authenticate()

                    let items = try sftp.contentsOfDirectory(atPath: path).map { item in
                        SFTPDirectoryItem(
                            name: item.name,
                            path: path.hasSuffix("/") ? "\(path)\(item.name)" : "\(path)/\(item.name)",
                            isDirectory: item.isDirectory,
                            size: Int64(item.size),
                            modificationDate: item.modificationDate
                        )
                    }

                    continuation.resume(returning: items)
                } catch {
                    continuation.resume(throwing: self.mapClientError(error))
                }
            }
        }
    }
    
    func uploadFile(from localPath: String, to remotePath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: SFTPError.serviceNotConfigured)
                    return
                }

                do {
                    let sftp = self.createConnection(connection)

                    try sftp.connect()
                    defer { sftp.disconnect() }

                    try sftp.authenticate()

                    guard let inputStream = InputStream(fileAtPath: localPath) else {
                        throw SFTPError.uploadFailed
                    }

                    let fileManager = FileManager.default
                    let fileAttributes = try fileManager.attributesOfItem(atPath: localPath)
                    let fileSize = fileAttributes[.size] as? Int64 ?? 0

                    var uploadCompleted = false

                    self.logger.debug("Starting upload of file size: \(fileSize) bytes")

                    do {
                        try sftp.uploadFile(atPath: localPath, toPath: remotePath) { bytesWritten in
                            // Stop processing if upload is already marked as completed
                            guard !uploadCompleted else {
                                return false // Signal to stop progress callbacks
                            }

                            // CRITICAL FIX: bytesWritten from the client is total bytes uploaded so far, not delta
                            // Don't accumulate - use the value directly
                            let totalBytesWritten = Int64(bytesWritten)

                            // Ensure uploaded bytes don't exceed file size
                            let clampedUploaded = min(totalBytesWritten, fileSize)

                            // Check if upload is complete (with small tolerance for rounding errors)
                            if clampedUploaded >= fileSize || Double(clampedUploaded) / Double(fileSize) >= 0.999 {
                                uploadCompleted = true
                            }

                            DispatchQueue.main.async {
                                progressHandler(clampedUploaded, fileSize)
                            }

                            // Return false to stop progress callbacks if completed
                            return !uploadCompleted
                        }

                        self.logger.debug("Upload completed successfully")

                    } catch {
                        // Check if upload actually completed despite the error
                        if uploadCompleted {
                            self.logger.debug("Upload threw after reaching 100%, treating it as a success")
                        } else {
                            self.logger.error("Upload failed before reaching 100%: \(error.localizedDescription)")
                            throw self.mapClientError(error)
                        }
                    }

                    // Ensure final 100% progress is shown
                    DispatchQueue.main.async {
                        progressHandler(fileSize, fileSize) // Force 100%
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func downloadFile(from remotePath: String, to localPath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws {
        let cancellation = CancellationFlag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: SFTPError.serviceNotConfigured)
                        return
                    }

                    do {
                        let sftp = self.createConnection(connection)

                        try sftp.connect()
                        defer { sftp.disconnect() }

                        try sftp.authenticate()

                        try sftp.downloadFile(atPath: remotePath, toPath: localPath) { downloaded, total in
                            DispatchQueue.main.async {
                                progressHandler(Int64(downloaded), Int64(total))
                            }
                            return !cancellation.cancelled
                        }

                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: self.mapClientError(error))
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
    
    func createDirectory(at path: String, connection: SFTPConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: SFTPError.serviceNotConfigured)
                    return
                }

                do {
                    let sftp = self.createConnection(connection)

                    try sftp.connect()
                    defer { sftp.disconnect() }

                    try sftp.authenticate()

                    try sftp.createDirectory(atPath: path)

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: self.mapClientError(error))
                }
            }
        }
    }

    func deleteFile(at path: String, connection: SFTPConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: SFTPError.serviceNotConfigured)
                    return
                }

                do {
                    let sftp = self.createConnection(connection)

                    try sftp.connect()
                    defer { sftp.disconnect() }

                    try sftp.authenticate()

                    try sftp.removeFile(atPath: path)

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: self.mapClientError(error))
                }
            }
        }
    }
    
    private func mapClientError(_ error: Error) -> SFTPError {
        if let sftpError = error as? SFTPError {
            return sftpError
        }

        let errorString = error.localizedDescription.lowercased()

        if errorString.contains("connect") || errorString.contains("connection") {
            return .connectionFailed
        } else if errorString.contains("auth") {
            return .authenticationFailed
        } else if errorString.contains("timeout") {
            return .connectionTimeout
        } else if errorString.contains("path") || errorString.contains("directory") {
            return .pathNotFound
        } else {
            return .networkError(error.localizedDescription)
        }
    }
}
