import Foundation
import Combine

struct TimeoutError: Error {
    let timeout: TimeInterval
}

func withTimeout<T: Sendable>(_ timeout: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TimeoutError(timeout: timeout)
        }

        guard let result = try await group.next() else {
            throw TimeoutError(timeout: timeout)
        }

        group.cancelAll()
        return result
    }
}

protocol PSFTPConnectionManager: AnyObject {
    func checkConnectionStatus(for connection: SFTPConnection, forceRefresh: Bool) async -> ConnectionStatus
    func checkAllConnectionStatuses(for connections: [SFTPConnection], forceRefresh: Bool) async
    func testConnection(_ connection: SFTPConnection, credentials: SFTPCredentials) async throws -> Bool
    func listDirectory(at path: String, connection: SFTPConnection) async throws -> [SFTPDirectoryItem]
    func uploadFile(from localPath: String, to remotePath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws
    func downloadFile(from remotePath: String, to localPath: String, connection: SFTPConnection, progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void) async throws
    func createDirectory(at path: String, connection: SFTPConnection) async throws
    func deleteFile(at path: String, connection: SFTPConnection) async throws
    func clearCache() async
    func clearCache(for connection: SFTPConnection) async
}

// Remove @MainActor - SFTP operations must NOT block main thread!
// UI updates will be explicitly done via MainActor.run where needed
class SFTPConnectionManager: ObservableObject, PSFTPConnectionManager {
    static let shared = SFTPConnectionManager()

    private var sftpService: PSFTPService?
    private var connectionStatusCache = [UUID: (status: ConnectionStatus, lastChecked: Date)]()
    // OPTIMIZED: Long cache validity to prevent repeated tests on screen switches
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes for better UX
    private let connectionTimeout: TimeInterval = 3 // Reduced from 10s to 3s

    // Use MainActor for Published properties only
    @MainActor @Published var connectionStatuses = [UUID: ConnectionStatus]()

    private init() {
        // Service will be injected later to avoid circular dependency
    }

    func configure(with sftpService: PSFTPService) {
        self.sftpService = sftpService
    }
    
    func checkConnectionStatus(for connection: SFTPConnection, forceRefresh: Bool = false) async -> ConnectionStatus {
        let cacheKey: UUID = connection.id

        // Check cache (fast, no MainActor needed for read)
        if !forceRefresh,
           let cached = connectionStatusCache[cacheKey],
           Date().timeIntervalSince(cached.lastChecked) < cacheValidityDuration {
            // Update UI on main thread
            await MainActor.run {
                self.connectionStatuses[cacheKey] = cached.status
            }
            return cached.status
        }

        // Update UI: Set connecting status
        await MainActor.run {
            self.connectionStatuses[cacheKey] = .connecting
        }

        // Perform connection test in BACKGROUND (not on main thread!)
        let status: ConnectionStatus
        do {
            let isConnected = try await withTimeout(connectionTimeout) {
                guard let sftpService = self.sftpService else {
                    throw SFTPError.serviceNotConfigured
                }
                return try await sftpService.testConnection(connection)
            }
            status = isConnected ? .connected : .error
        } catch is TimeoutError {
            status = .error
        } catch {
            status = .error
        }

        // Update cache (background thread is fine)
        let statusEntry: (status: ConnectionStatus, lastChecked: Date) = (status: status, lastChecked: Date())
        connectionStatusCache.updateValue(statusEntry, forKey: cacheKey)

        // Update UI on main thread
        await MainActor.run {
            self.connectionStatuses[cacheKey] = status
        }

        return status
    }
    
    func checkAllConnectionStatuses(for connections: [SFTPConnection], forceRefresh: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for connection in connections {
                group.addTask {
                    await self.checkConnectionStatus(for: connection, forceRefresh: forceRefresh)
                }
            }
        }
    }
    
    func testConnection(_ connection: SFTPConnection, credentials: SFTPCredentials) async throws -> Bool {
        guard let sftpService = sftpService else {
            throw SFTPError.serviceNotConfigured
        }
        return try await sftpService.testConnectionWithCredentials(connection, credentials: credentials)
    }
    
    func listDirectory(at path: String, connection: SFTPConnection) async throws -> [SFTPDirectoryItem] {
        guard let sftpService = sftpService else {
            throw SFTPError.serviceNotConfigured
        }
        return try await sftpService.listDirectory(at: path, connection: connection)
    }
    
    func uploadFile(
        from localPath: String,
        to remotePath: String,
        connection: SFTPConnection,
        progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void
    ) async throws {
        guard let sftpService = sftpService else {
            throw SFTPError.serviceNotConfigured
        }
        try await sftpService.uploadFile(
            from: localPath,
            to: remotePath,
            connection: connection,
            progressHandler: progressHandler
        )
    }
    
    func downloadFile(
        from remotePath: String,
        to localPath: String,
        connection: SFTPConnection,
        progressHandler: @escaping @Sendable @MainActor (Int64, Int64) -> Void
    ) async throws {
        guard let sftpService = sftpService else {
            throw SFTPError.serviceNotConfigured
        }
        try await sftpService.downloadFile(
            from: remotePath,
            to: localPath,
            connection: connection,
            progressHandler: progressHandler
        )
    }
    
    func createDirectory(at path: String, connection: SFTPConnection) async throws {
        guard let sftpService = sftpService else {
            throw SFTPError.serviceNotConfigured
        }
        try await sftpService.createDirectory(at: path, connection: connection)
    }

    func deleteFile(at path: String, connection: SFTPConnection) async throws {
        guard let sftpService = sftpService else {
            throw SFTPError.serviceNotConfigured
        }
        try await sftpService.deleteFile(at: path, connection: connection)
    }

    func clearCache() async {
        connectionStatusCache.removeAll()
        await MainActor.run {
            self.connectionStatuses.removeAll()
        }
    }

    func clearCache(for connection: SFTPConnection) async {
        let cacheKey: UUID = connection.id
        connectionStatusCache.removeValue(forKey: cacheKey)
        await MainActor.run {
            self.connectionStatuses.removeValue(forKey: cacheKey)
        }
    }
}
