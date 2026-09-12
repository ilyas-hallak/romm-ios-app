//
//  ScanEventMapper.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

/// Turns raw socket events into the domain events the live view consumes.
/// Anything unknown or undecodable is dropped rather than surfaced.
struct ScanEventMapper {
    enum EventName {
        static let scanningPlatform = "scan:scanning_platform"
        static let scanningRom = "scan:scanning_rom"
        static let updateStats = "scan:update_stats"
        static let done = "scan:done"
        static let failed = "scan:done_ko"
    }

    static func map(_ event: SocketIOEvent) -> LibraryScanEvent? {
        switch event.name {
        case EventName.scanningPlatform:
            guard let platform = decode(ScanPlatformSchema.self, from: event.data) else { return nil }
            return .platform(mapPlatform(platform))
        case EventName.scanningRom:
            guard let rom = decode(ScanRomSchema.self, from: event.data) else { return nil }
            return .rom(mapRom(rom))
        case EventName.updateStats:
            guard let stats = decode(ScanStatsSchema.self, from: event.data) else { return nil }
            return .stats(mapStats(stats))
        case EventName.done:
            return .finished
        case EventName.failed:
            return .failed(reason(from: event.data))
        default:
            return nil
        }
    }

    // MARK: - Payloads

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// `scan:done_ko` carries a plain string, not an object.
    private static func reason(from data: Data?) -> String {
        guard let data else { return "The scan failed." }
        if let decoded = try? JSONDecoder().decode(String.self, from: data), !decoded.isEmpty {
            return decoded
        }
        let raw = String(data: data, encoding: .utf8) ?? ""
        let unquoted = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return unquoted.isEmpty ? "The scan failed." : unquoted
    }

    // MARK: - Mapping

    private static func mapPlatform(_ schema: ScanPlatformSchema) -> LibraryScanPlatform {
        let name = schema.displayName ?? schema.name ?? schema.slug ?? "Unknown platform"
        return LibraryScanPlatform(
            id: schema.id ?? 0,
            name: schema.name ?? name,
            displayName: name,
            slug: schema.slug ?? schema.fsSlug ?? "",
            isIdentified: schema.isIdentified ?? false,
            newFirmwareCount: schema.newFirmwareCount ?? 0
        )
    }

    private static func mapRom(_ schema: ScanRomSchema) -> LibraryScanRom {
        let name = schema.name ?? schema.fsName ?? "Unknown ROM"
        return LibraryScanRom(
            romId: schema.id,
            name: name,
            fileName: schema.fsName,
            platformName: schema.platformName ?? schema.platformSlug
        )
    }

    private static func mapStats(_ schema: ScanStatsSchema) -> LibraryScanStats {
        LibraryScanStats(
            totalPlatforms: schema.totalPlatforms,
            totalRoms: schema.totalRoms,
            scannedPlatforms: schema.scannedPlatforms,
            newPlatforms: schema.newPlatforms,
            identifiedPlatforms: schema.identifiedPlatforms,
            scannedRoms: schema.scannedRoms,
            newRoms: schema.newRoms,
            identifiedRoms: schema.identifiedRoms,
            scannedFirmware: schema.scannedFirmware,
            newFirmware: schema.newFirmware
        )
    }
}
