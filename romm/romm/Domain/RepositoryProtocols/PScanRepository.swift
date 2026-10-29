//
//  PScanRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

protocol PScanRepository {
    /// Queues a scan over `POST /api/tasks/scan`. Throws `ScanStartError.refused`
    /// when the server declines it (a scan is already running, or no worker is
    /// listening), any other error when the request itself failed. The caller
    /// follows the run through `PTasksRepository`.
    func startScan(type: LibraryScanType, platformIds: [Int]) async throws
}
