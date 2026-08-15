//
//  SyncModels.swift
//  romm
//
//  DTOs for the RomM save-sync API (device registration + negotiate delta),
//  available on RomM 5.0+. See issue #48.
//

import Foundation

// MARK: - Devices

/// Body for `POST /api/devices` — registers this app instance as a sync device.
struct DeviceRegisterRequest: Codable {
    let name: String
    let platform: String
    let client: String
    /// One of `api | file_transfer | push_pull`.
    let syncMode: String

    enum CodingKeys: String, CodingKey {
        case name, platform, client
        case syncMode = "sync_mode"
    }
}

/// Response of `POST /api/devices` (`DeviceCreateResponse` → `device_id`) and
/// `GET /api/devices/{id}` (`DeviceSchema` → `id`). The identifier is a string
/// on the server (5.1); decoding tolerates either key.
struct DeviceSchema: Codable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
    }

    init(id: String) { self.id = id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let did = try c.decodeIfPresent(String.self, forKey: .deviceId) {
            id = did
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
    }
}

// MARK: - Negotiate

/// One local save/state the client reports during sync negotiation.
struct ClientSaveState: Codable {
    let romId: Int
    let fileName: String
    let slot: String?
    let emulator: String?
    let contentHash: String
    let updatedAt: Date
    let fileSizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case romId = "rom_id"
        case fileName = "file_name"
        case slot
        case emulator
        case contentHash = "content_hash"
        case updatedAt = "updated_at"
        case fileSizeBytes = "file_size_bytes"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(romId, forKey: .romId)
        try c.encode(fileName, forKey: .fileName)
        try c.encodeIfPresent(slot, forKey: .slot)
        try c.encodeIfPresent(emulator, forKey: .emulator)
        try c.encode(contentHash, forKey: .contentHash)
        // Match the server's ISO-8601 wire format instead of the JSONEncoder
        // default (epoch double), which the sync router rejects.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        try c.encode(iso.string(from: updatedAt), forKey: .updatedAt)
        try c.encode(fileSizeBytes, forKey: .fileSizeBytes)
    }
}

/// Body for `POST /api/sync/negotiate`.
struct SyncNegotiateRequest: Codable {
    let deviceId: String
    let saves: [ClientSaveState]

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case saves
    }
}

/// The action the server wants performed for one save/state.
enum SyncAction: String, Codable {
    case upload
    case download
    case conflict
    case noOp = "no_op"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = SyncAction(rawValue: raw) ?? .unknown
    }
}

/// One planned operation returned by negotiate. All fields but `action` are
/// optional so a schema drift on the server never fails the whole response.
struct SyncOperationSchema: Codable {
    let action: SyncAction
    let romId: Int?
    let saveId: Int?
    let fileName: String?
    let slot: String?
    let emulator: String?
    let reason: String?
    let serverUpdatedAt: Date?
    let serverContentHash: String?

    enum CodingKeys: String, CodingKey {
        case action
        case romId = "rom_id"
        case saveId = "save_id"
        case fileName = "file_name"
        case slot
        case emulator
        case reason
        case serverUpdatedAt = "server_updated_at"
        case serverContentHash = "server_content_hash"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = (try? c.decode(SyncAction.self, forKey: .action)) ?? .unknown
        romId = try? c.decodeIfPresent(Int.self, forKey: .romId)
        saveId = try? c.decodeIfPresent(Int.self, forKey: .saveId)
        fileName = try? c.decodeIfPresent(String.self, forKey: .fileName)
        slot = try? c.decodeIfPresent(String.self, forKey: .slot)
        emulator = try? c.decodeIfPresent(String.self, forKey: .emulator)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        let parsedDate: Date? = try? c.decodeFlexibleDate(forKey: CodingKeys.serverUpdatedAt)
        serverUpdatedAt = parsedDate
        serverContentHash = try? c.decodeIfPresent(String.self, forKey: .serverContentHash)
    }
}

/// Response of `POST /api/sync/negotiate`.
struct SyncNegotiateResponse: Codable {
    let sessionId: String?
    let operations: [SyncOperationSchema]
    let totalUpload: Int?
    let totalDownload: Int?
    let totalConflict: Int?
    let totalNoOp: Int?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case operations
        case totalUpload = "total_upload"
        case totalDownload = "total_download"
        case totalConflict = "total_conflict"
        case totalNoOp = "total_no_op"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // session_id may arrive as string or int; accept either.
        if let s = try? c.decodeIfPresent(String.self, forKey: .sessionId) {
            sessionId = s
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .sessionId) {
            sessionId = String(i)
        } else {
            sessionId = nil
        }
        operations = (try? c.decodeIfPresent([SyncOperationSchema].self, forKey: .operations)) ?? []
        totalUpload = try? c.decodeIfPresent(Int.self, forKey: .totalUpload)
        totalDownload = try? c.decodeIfPresent(Int.self, forKey: .totalDownload)
        totalConflict = try? c.decodeIfPresent(Int.self, forKey: .totalConflict)
        totalNoOp = try? c.decodeIfPresent(Int.self, forKey: .totalNoOp)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sessionId, forKey: .sessionId)
        try c.encode(operations, forKey: .operations)
        try c.encodeIfPresent(totalUpload, forKey: .totalUpload)
        try c.encodeIfPresent(totalDownload, forKey: .totalDownload)
        try c.encodeIfPresent(totalConflict, forKey: .totalConflict)
        try c.encodeIfPresent(totalNoOp, forKey: .totalNoOp)
    }
}
