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
}
