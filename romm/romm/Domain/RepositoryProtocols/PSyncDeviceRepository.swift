//
//  PSyncDeviceRepository.swift
//  romm
//
//  Protocol for the sync-device repository. Owns this app instance's RomM
//  sync device identity (register once, persist the id). See issue #48.
//

import Foundation

protocol PSyncDeviceRepository {
    /// Whether the connected server is new enough to expose the sync API
    /// (>= 4.9.0). Based on the version cached by the heartbeat at login.
    var isSyncAPISupported: Bool { get }

    /// Returns a registered device id, registering once if needed. Returns
    /// `nil` when the server is too old or registration fails, so callers can
    /// fall back to the legacy full-sync path.
    func deviceId() async -> String?
}
