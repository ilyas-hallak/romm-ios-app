//
//  TasksRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

class TasksRepository: PTasksRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient

    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }

    func getLatestLibraryScan() async throws -> LibraryScanStatus? {
        logger.info("Getting task status from API...")

        do {
            let apiTasks = try await apiClient.getTasksStatus()

            // The array is already sorted newest first by the server, so the
            // first scan task is the current or most recent run. Matching on
            // task_type is the only reliable filter, task_name carries the
            // human label of the run, e.g. "Quick Scan".
            guard let latestScan = apiTasks.first(where: { $0.taskType == "scan" }) else {
                logger.info("No library scan task found")
                return nil
            }

            let domainScan = TasksMapper.mapFromAPI(latestScan)
            logger.info("Retrieved latest library scan: \(domainScan.name), \(domainScan.state)")
            return domainScan
        } catch {
            logger.error("Error getting task status: \(error)")
            throw error
        }
    }
}
