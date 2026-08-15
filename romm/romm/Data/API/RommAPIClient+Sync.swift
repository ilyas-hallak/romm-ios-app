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
}
