//
//  TaskStatusSchema.swift
//  romm
//
//  DTOs for `GET /api/tasks/status` (issue #160). The endpoint returns a flat
//  array of task status objects, newest first, and only scan tasks carry
//  scan_stats in their meta payload.
//

import Foundation

struct TaskStatusSchema: Codable {
    let taskName: String
    let taskId: String
    let taskType: String
    let status: String
    let createdAt: Date?
    let enqueuedAt: Date?
    let startedAt: Date?
    let endedAt: Date?
    let scanStats: ScanStatsSchema?

    enum CodingKeys: String, CodingKey {
        case taskName = "task_name"
        case taskId = "task_id"
        case taskType = "task_type"
        case status
        case createdAt = "created_at"
        case enqueuedAt = "enqueued_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case meta
    }

    private enum MetaCodingKeys: String, CodingKey {
        case scanStats = "scan_stats"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskName = container.decodeOrDefault(String.self, forKey: .taskName, default: "")
        taskId = container.decodeOrDefault(String.self, forKey: .taskId, default: "")
        taskType = container.decodeOrDefault(String.self, forKey: .taskType, default: "")
        status = container.decodeOrDefault(String.self, forKey: .status, default: "")

        // Dates may be null or missing outright, so decode flexibly and never throw.
        if container.contains(.createdAt) {
            createdAt = try? container.decodeFlexibleDate(forKey: .createdAt)
        } else {
            createdAt = nil
        }
        if container.contains(.enqueuedAt) {
            enqueuedAt = try? container.decodeFlexibleDate(forKey: .enqueuedAt)
        } else {
            enqueuedAt = nil
        }
        if container.contains(.startedAt) {
            startedAt = try? container.decodeFlexibleDate(forKey: .startedAt)
        } else {
            startedAt = nil
        }
        if container.contains(.endedAt) {
            endedAt = try? container.decodeFlexibleDate(forKey: .endedAt)
        } else {
            endedAt = nil
        }

        if let metaContainer = try? container.nestedContainer(keyedBy: MetaCodingKeys.self, forKey: .meta) {
            scanStats = try? metaContainer.decodeIfPresent(ScanStatsSchema.self, forKey: .scanStats)
        } else {
            scanStats = nil
        }
    }

    // This DTO is response-only, but the API client's generic `get` requires
    // Codable, not just Decodable, so provide a straightforward encode too.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(taskName, forKey: .taskName)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(taskType, forKey: .taskType)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(enqueuedAt, forKey: .enqueuedAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)

        if let scanStats {
            var metaContainer = container.nestedContainer(keyedBy: MetaCodingKeys.self, forKey: .meta)
            try metaContainer.encode(scanStats, forKey: .scanStats)
        }
    }
}

struct ScanStatsSchema: Codable {
    let totalPlatforms: Int
    let totalRoms: Int
    let scannedPlatforms: Int
    let newPlatforms: Int
    let identifiedPlatforms: Int
    let scannedRoms: Int
    let newRoms: Int
    let identifiedRoms: Int
    let scannedFirmware: Int
    let newFirmware: Int

    enum CodingKeys: String, CodingKey {
        case totalPlatforms = "total_platforms"
        case totalRoms = "total_roms"
        case scannedPlatforms = "scanned_platforms"
        case newPlatforms = "new_platforms"
        case identifiedPlatforms = "identified_platforms"
        case scannedRoms = "scanned_roms"
        case newRoms = "new_roms"
        case identifiedRoms = "identified_roms"
        case scannedFirmware = "scanned_firmware"
        case newFirmware = "new_firmware"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalPlatforms = container.decodeOrDefault(Int.self, forKey: .totalPlatforms, default: 0)
        totalRoms = container.decodeOrDefault(Int.self, forKey: .totalRoms, default: 0)
        scannedPlatforms = container.decodeOrDefault(Int.self, forKey: .scannedPlatforms, default: 0)
        newPlatforms = container.decodeOrDefault(Int.self, forKey: .newPlatforms, default: 0)
        identifiedPlatforms = container.decodeOrDefault(Int.self, forKey: .identifiedPlatforms, default: 0)
        scannedRoms = container.decodeOrDefault(Int.self, forKey: .scannedRoms, default: 0)
        newRoms = container.decodeOrDefault(Int.self, forKey: .newRoms, default: 0)
        identifiedRoms = container.decodeOrDefault(Int.self, forKey: .identifiedRoms, default: 0)
        scannedFirmware = container.decodeOrDefault(Int.self, forKey: .scannedFirmware, default: 0)
        newFirmware = container.decodeOrDefault(Int.self, forKey: .newFirmware, default: 0)
    }
}
