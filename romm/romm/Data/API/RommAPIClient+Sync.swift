//
//  RommAPIClient+Sync.swift
//  romm
//
//  RomM 5.0+ save-sync endpoints: device registration, negotiate, session
//  bookkeeping. See #48 and #144.
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

    /// `POST /api/sync/sessions/{id}/complete` — closes the session negotiation
    /// opened. Every negotiation starts one, so a plan that is abandoned still
    /// has to be reported, or the session is left open on the server for good.
    func completeSyncSession(
        id: Int,
        operationsCompleted: Int,
        operationsFailed: Int
    ) async throws -> SyncSessionSchema {
        let body = SyncCompleteRequest(
            operationsCompleted: operationsCompleted,
            operationsFailed: operationsFailed
        )
        let response = try await post(
            "api/sync/sessions/\(id)/complete",
            body: body,
            responseType: SyncCompleteResponse.self
        )
        return response.session
    }
}
