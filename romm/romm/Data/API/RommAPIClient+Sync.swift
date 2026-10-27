//
//  RommAPIClient+Sync.swift
//  romm
//
//  RomM 5.0+ save-sync endpoints: device registration + negotiate. See #48.
//

import Foundation

extension RommAPIClient {

    /// `POST /api/devices` — registers this app instance and returns its id.
    func registerDevice(_ body: DeviceRegisterRequest) async throws -> DeviceSchema {
        try await post("api/devices", body: body, responseType: DeviceSchema.self)
    }

    /// `POST /api/sync/negotiate` — sends what we have locally and gets back a
    /// per-save plan (upload / download / conflict / no-op).
    func negotiateSync(_ body: SyncNegotiateRequest) async throws -> SyncNegotiateResponse {
        try await post("api/sync/negotiate", body: body, responseType: SyncNegotiateResponse.self)
    }

    /// `POST /api/sync/sessions/{sessionId}/complete` — closes out the session
    /// opened by `negotiate` with how many operations actually succeeded. The
    /// response carries nothing callers need, so it is decoded into an empty
    /// struct purely to satisfy `post`'s Codable requirement.
    func completeSyncSession(sessionId: String, operationsCompleted: Int, operationsFailed: Int) async throws {
        struct Body: Codable {
            let operationsCompleted: Int
            let operationsFailed: Int
            enum CodingKeys: String, CodingKey {
                case operationsCompleted = "operations_completed"
                case operationsFailed = "operations_failed"
            }
        }
        struct EmptyResponse: Codable {}
        _ = try await post(
            "api/sync/sessions/\(sessionId)/complete",
            body: Body(operationsCompleted: operationsCompleted, operationsFailed: operationsFailed),
            responseType: EmptyResponse.self
        )
    }
}
