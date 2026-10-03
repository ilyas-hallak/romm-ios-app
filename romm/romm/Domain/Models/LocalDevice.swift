import Foundation
import UIKit

/// Represents the current iOS device (iPhone/iPad) as a download target
struct LocalDevice: PDevice, Codable {
    let id: UUID
    var name: String
    var isDefault: Bool
    var lastConnectedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    // Local device specific properties
    let deviceModel: String
    let systemVersion: String
    var availableStorageBytes: Int64
    var totalStorageBytes: Int64

    var deviceType: DeviceType {
        return .local
    }

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case id, name, isDefault, lastConnectedAt, createdAt, updatedAt
        case deviceModel, systemVersion, availableStorageBytes, totalStorageBytes
    }

    init(
        id: UUID = UUID(),
        name: String,
        isDefault: Bool = true,
        lastConnectedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deviceModel: String,
        systemVersion: String,
        availableStorageBytes: Int64,
        totalStorageBytes: Int64
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.lastConnectedAt = lastConnectedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deviceModel = deviceModel
        self.systemVersion = systemVersion
        self.availableStorageBytes = availableStorageBytes
        self.totalStorageBytes = totalStorageBytes
    }

    // MARK: - Computed Properties

    var availableStorageFormatted: String {
        ByteCountFormatter.string(fromByteCount: availableStorageBytes, countStyle: .file)
    }

    var totalStorageFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }

    var hasLowStorage: Bool {
        // Consider storage low if less than 1GB available
        return availableStorageBytes < 1_000_000_000
    }

    // MARK: - Static Factory

    /// Creates a LocalDevice instance representing the current device
    static func current() -> LocalDevice {
        let deviceName = UIDevice.current.name
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion

        let fileManager = FileManager.default
        let documentURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        // Get available storage
        var availableBytes: Int64 = 0
        var totalBytes: Int64 = 0

        do {
            let values = try documentURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])

            availableBytes = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            totalBytes = Int64(values.volumeTotalCapacity ?? 0)
        } catch {
            print("Error retrieving storage info: \(error)")
        }

        return LocalDevice(
            name: deviceName,
            isDefault: true,
            deviceModel: deviceModel,
            systemVersion: systemVersion,
            availableStorageBytes: availableBytes,
            totalStorageBytes: totalBytes
        )
    }

    // MARK: - Storage Update

    /// Updates the storage information for this device
    mutating func updateStorageInfo() {
        let fileManager = FileManager.default
        let documentURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        do {
            let values = try documentURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])

            availableStorageBytes = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            totalStorageBytes = Int64(values.volumeTotalCapacity ?? 0)
            updatedAt = Date()
        } catch {
            print("Error updating storage info: \(error)")
        }
    }

    /// Checks if there's enough storage for a given file size
    func hasEnoughStorage(for sizeInBytes: Int64) -> Bool {
        // Add a 10% buffer for safety
        let requiredBytes = Int64(Double(sizeInBytes) * 1.1)
        return availableStorageBytes >= requiredBytes
    }

    // MARK: - Equatable

    static func == (lhs: LocalDevice, rhs: LocalDevice) -> Bool {
        return lhs.id == rhs.id
    }
}
