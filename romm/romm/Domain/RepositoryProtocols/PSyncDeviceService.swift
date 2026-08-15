//
//  PSyncDeviceService.swift
//  romm
//

import Foundation

/// Protocol for the sync-device service used by CloudSaveSyncService.
/// Abstracts device registration and version-gate so callers are not
/// coupled to the concrete SyncDeviceService singleton.
@MainActor
protocol PSyncDeviceService {
    /// Whether the connected server is new enough to expose the sync API.
    var isSyncAPISupported: Bool { get }

    /// Returns a registered device id, registering once if needed. Returns
    /// `nil` when the server is too old or registration fails, so callers
    /// can fall back to the legacy full-sync path.
    func deviceId() async -> String?
}
