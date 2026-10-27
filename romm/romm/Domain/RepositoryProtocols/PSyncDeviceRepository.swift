
import Foundation

/// Whether the connected server can sync saves at all.
enum SyncAPIAvailability: Equatable {
    case available
    /// The server's version is below the sync API's.
    case serverTooOld(version: String)
    /// No version could be established, usually a server that has not been
    /// reached yet. Not the same as too old.
    case unknown
}

protocol PSyncDeviceRepository {
    /// Whether the server exposes the sync API (>= 4.9.0). Async because an
    /// uncached version costs one request rather than a wrong verdict.
    func syncAPIAvailability() async -> SyncAPIAvailability

    /// A registered device id, registering once if needed. Nil when the server
    /// is too old or registration fails, so callers can fall back.
    func deviceId() async -> String?

    /// Drops the stored registration, so the next ``deviceId()`` registers
    /// again. For the case where the server no longer knows this device, which
    /// it answers with a 404 and which nothing else here recovers from.
    func forgetDevice()

    /// Closes out a sync session opened by `negotiate`, so the server's own
    /// bookkeeping reflects what actually happened. Best effort: callers should
    /// treat a thrown error as a log warning, not a run failure.
    func completeSyncSession(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws
}
