//
//  SyncDeviceRepository.swift
//  romm
//
//  Registers this app instance as a RomM sync device once and persists its id.
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
        // The cache is only written by a successful version check, so it is
        // also empty before the first one. Empty does not mean old.
        guard let fetched = try? await heartbeat.getHeartbeat().version else { return .unknown }
        // Not cached here: that write arms HeartbeatRepository's "version
        // changed" warning, which is the version check's to raise.
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

    /// A registered device id, registering once if needed. Nil when the server
    /// is too old or registration fails, so callers can fall back.
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

    /// Minimal semantic-version compare, kept here so this repository stays
    /// self-contained.
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
