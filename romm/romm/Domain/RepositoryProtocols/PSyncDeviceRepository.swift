//
//  PSyncDeviceRepository.swift
//  romm
//
//  Protocol for the sync-device repository. Owns this app instance's RomM
//  sync device identity (register once, persist the id). See issue #48.
//

import Foundation

/// Whether the connected server can sync saves at all.
enum SyncAPIAvailability: Equatable {
    case available
    /// The server's version is below the sync API's.
    case serverTooOld(version: String)
    /// No version could be established. Not the same as too old: the usual
    /// cause is a server that has not been reached yet, or one newer than this
    /// build supports, since neither leaves a cached version behind.
    case unknown
}

protocol PSyncDeviceRepository {
    /// Whether the connected server is new enough to expose the sync API
    /// (>= 4.9.0).
    ///
    /// Asynchronous because an uncached version is worth one request: answering
    /// "too old" for a server that was simply never checked tells the user the
    /// opposite of the truth.
    func syncAPIAvailability() async -> SyncAPIAvailability

    /// Returns a registered device id, registering once if needed. Returns
    /// `nil` when the server is too old or registration fails, so callers can
    /// fall back to the legacy full-sync path.
    func deviceId() async -> String?
}
