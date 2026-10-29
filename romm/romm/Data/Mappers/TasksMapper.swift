//
//  TasksMapper.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

struct TasksMapper {
    static func mapFromAPI(_ apiTask: TaskStatusSchema) -> LibraryScanStatus {
        return LibraryScanStatus(
            id: apiTask.taskId,
            name: apiTask.taskName,
            state: mapState(apiTask.status),
            startedAt: apiTask.startedAt,
            endedAt: apiTask.endedAt,
            stats: apiTask.scanStats.map(mapStats)
        )
    }

    private static func mapState(_ status: String) -> LibraryScanState {
        switch status {
        case "queued", "scheduled", "deferred":
            return .queued
        case "started":
            return .running
        case "finished":
            return .finished
        case "failed":
            return .failed
        case "stopped", "canceled":
            return .stopped
        default:
            return .unknown
        }
    }

    private static func mapStats(_ apiStats: ScanStatsSchema) -> LibraryScanStats {
        return LibraryScanStats(
            totalPlatforms: apiStats.totalPlatforms,
            totalRoms: apiStats.totalRoms,
            scannedPlatforms: apiStats.scannedPlatforms,
            newPlatforms: apiStats.newPlatforms,
            identifiedPlatforms: apiStats.identifiedPlatforms,
            scannedRoms: apiStats.scannedRoms,
            newRoms: apiStats.newRoms,
            identifiedRoms: apiStats.identifiedRoms,
            scannedFirmware: apiStats.scannedFirmware,
            newFirmware: apiStats.newFirmware
        )
    }
}
