//
//  SyncDeviceService.swift
//  romm
//
//  Owns this app instance's RomM sync device identity. Registers the device
//  once (RomM 5.0+) and persists its id so the negotiate flow can reference it.
//  See issue #48.
//

import Foundation
import UIKit

@MainActor
final class SyncDeviceService: PSyncDeviceService {
    static let shared = SyncDeviceService()

    private let apiClient: PRommAPIClient
    private let userDefaults: UserDefaults
    private let heartbeat: PHeartbeatRepository

    /// The device + sync negotiate routers are available from RomM 4.9.0.
    private let minSyncVersion = "4.9.0"
    private let deviceIdKey = "sync.deviceId"

    /// Guards against parallel emulator launches each firing a registration.
    private var inFlight: Task<String?, Never>?

    init(
        apiClient: PRommAPIClient = RommAPIClient.shared,
        userDefaults: UserDefaults = .standard,
        heartbeat: PHeartbeatRepository = HeartbeatRepository()
    ) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
        self.heartbeat = heartbeat
    }

    /// Whether the connected server is new enough to expose the sync API. Based
    /// on the version cached by the heartbeat check at login/connect.
    var isSyncAPISupported: Bool {
        guard let version = heartbeat.getLastKnownServerVersion() else { return false }
        return Self.compareVersions(version, minSyncVersion) >= 0
    }

    private var storedDeviceId: String? {
        let v = userDefaults.string(forKey: deviceIdKey)
        return (v?.isEmpty == false) ? v : nil
    }

    /// Returns a registered device id, registering once if needed. Returns
    /// `nil` when the server is too old or registration fails, so callers can
    /// fall back to the legacy full-sync path.
    func deviceId() async -> String? {
        if let id = storedDeviceId { return id }
        guard isSyncAPISupported else { return nil }

        if let inFlight { return await inFlight.value }
        let task = Task<String?, Never> { [apiClient, userDefaults, deviceIdKey] in
            let request = DeviceRegisterRequest(
                name: await MainActor.run { UIDevice.current.name },
                platform: "ios",
                client: "romm-ios",
                syncMode: "api"
            )
            do {
                let device = try await apiClient.registerDevice(request)
                userDefaults.set(device.id, forKey: deviceIdKey)
                print("[SyncDevice] registered device id=\(device.id)")
                return device.id
            } catch {
                print("[SyncDevice] registration failed: \(error.localizedDescription)")
                return nil
            }
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    // MARK: - Version compare

    /// Minimal semantic-version compare; mirrors HeartbeatRepository's logic so
    /// this service stays self-contained.
    private static func compareVersions(_ a: String, _ b: String) -> Int {
        if a == "development" { return 1 }
        if b == "development" { return -1 }
        let baseA = a.split(separator: "-").first.map(String.init) ?? a
        let baseB = b.split(separator: "-").first.map(String.init) ?? b
        let pa = baseA.split(separator: ".").compactMap { Int($0) }
        let pb = baseB.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x < y { return -1 }
            if x > y { return 1 }
        }
        return 0
    }
}
