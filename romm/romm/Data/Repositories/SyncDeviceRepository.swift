//
//  SyncDeviceRepository.swift
//  romm
//
//  Owns this app instance's RomM sync device identity. Registers the device
//  once (RomM 4.9+) and persists its id so the negotiate flow can reference it.
//  See issue #48.
//

import Foundation
import UIKit

final class SyncDeviceRepository: PSyncDeviceRepository {
    private let logger = Logger.sync
    private let apiClient: PRommAPIClient
    private let userDefaults: UserDefaults
    private let heartbeat: PHeartbeatRepository

    /// The device + sync negotiate routers are available from RomM 4.9.0.
    private let minSyncVersion = "4.9.0"
    private let deviceIdKey = "sync.deviceId"

    /// Guards against parallel emulator launches each firing a registration.
    private var inFlight: Task<String?, Never>?

    init(
        apiClient: PRommAPIClient,
        userDefaults: UserDefaults = .standard,
        heartbeat: PHeartbeatRepository
    ) {
        self.apiClient = apiClient
        self.userDefaults = userDefaults
        self.heartbeat = heartbeat
    }

    func syncAPIAvailability() async -> SyncAPIAvailability {
        if let cached = heartbeat.getLastKnownServerVersion() {
            return availability(for: cached)
        }
        // The cache is only written by a *successful* version check, so it is
        // empty both before the first check and for a server this build
        // considers out of range. Neither means old, so the version is asked
        // for rather than assumed.
        guard let fetched = try? await heartbeat.getHeartbeat().version else { return .unknown }
        // Not written back: that write also arms HeartbeatRepository's "server
        // version changed" warning, which is the version check's to raise.
        return availability(for: fetched)
    }

    private func availability(for version: String) -> SyncAPIAvailability {
        Self.compareVersions(version, minSyncVersion) >= 0
            ? .available
            : .serverTooOld(version: version)
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
        guard case .available = await syncAPIAvailability() else { return nil }

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
                self.logger.info("Registered sync device id=\(device.id)")
                return device.id
            } catch {
                self.logger.error("Device registration failed: \(error.localizedDescription)")
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
    /// this repository stays self-contained.
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
