
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
}
