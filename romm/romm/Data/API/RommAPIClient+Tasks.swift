//
//  RommAPIClient+Tasks.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

// MARK: - Tasks API
extension RommAPIClient {
    func getTasksStatus() async throws -> [TaskStatusSchema] {
        return try await get("api/tasks/status", responseType: [TaskStatusSchema].self)
    }

    /// Queues a scan with the existing Bearer/client-token auth, no Socket.IO
    /// session required (RomM 5.4.0+). The server answers 409 while a scan is
    /// already queued or running, 503 when no scan worker is listening.
    func startLibraryScan(_ request: ScanStartRequest) async throws {
        let body = try JSONEncoder().encode(request)
        _ = try await post("api/tasks/scan", body: body)
    }
}
