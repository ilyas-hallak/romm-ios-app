//
//  TasksMapperTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct TasksMapperTests {

    private static func schema(status: String, scanStats: ScanStatsSchema? = nil) -> TaskStatusSchema {
        let json = """
        {
            "task_name": "Quick Scan",
            "task_id": "abc-123",
            "task_type": "scan",
            "status": "\(status)"
        }
        """
        return try! JSONDecoder().decode(TaskStatusSchema.self, from: Data(json.utf8))
    }

    @Test(arguments: [
        ("queued", LibraryScanState.queued),
        ("scheduled", .queued),
        ("deferred", .queued),
        ("started", .running),
        ("finished", .finished),
        ("failed", .failed),
        ("stopped", .stopped),
        ("canceled", .stopped),
        ("something_new", .unknown)
    ])
    func mapsEveryServerStatusToItsState(status: String, expected: LibraryScanState) {
        let domain = TasksMapper.mapFromAPI(Self.schema(status: status))

        #expect(domain.state == expected)
        #expect(domain.id == "abc-123")
        #expect(domain.name == "Quick Scan")
    }

    @Test func carriesTheScanStatsThrough() throws {
        let json = """
        {
            "task_name": "Quick Scan",
            "task_id": "abc-123",
            "task_type": "scan",
            "status": "started",
            "meta": {
                "scan_stats": {
                    "total_platforms": 10,
                    "total_roms": 500,
                    "scanned_platforms": 3,
                    "new_platforms": 1,
                    "identified_platforms": 2,
                    "scanned_roms": 120,
                    "new_roms": 12,
                    "identified_roms": 100,
                    "scanned_firmware": 4,
                    "new_firmware": 1
                }
            }
        }
        """
        let schema = try JSONDecoder().decode(TaskStatusSchema.self, from: Data(json.utf8))

        let domain = TasksMapper.mapFromAPI(schema)

        let stats = try #require(domain.stats)
        #expect(stats.totalRoms == 500)
        #expect(stats.scannedRoms == 120)
        #expect(stats.newRoms == 12)
    }

    @Test func aNonScanTaskHasNoStats() throws {
        let json = """
        {
            "task_name": "Cleanup",
            "task_id": "abc-123",
            "task_type": "cleanup",
            "status": "finished"
        }
        """
        let schema = try JSONDecoder().decode(TaskStatusSchema.self, from: Data(json.utf8))

        let domain = TasksMapper.mapFromAPI(schema)

        #expect(domain.stats == nil)
    }
}
