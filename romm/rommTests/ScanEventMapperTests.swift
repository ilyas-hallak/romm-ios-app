//
//  ScanEventMapperTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct ScanEventMapperTests {

    private func event(_ name: String, _ json: String?) -> SocketIOEvent {
        SocketIOEvent(name: name, data: json?.data(using: .utf8))
    }

    // MARK: - Platforms

    @Test func mapsAScannedPlatform() {
        let mapped = ScanEventMapper.map(event("scan:scanning_platform", """
        {
          "id": 3,
          "name": "Super Nintendo",
          "display_name": "SNES",
          "slug": "snes",
          "fs_slug": "snes",
          "is_identified": true,
          "new_firmware_count": 2
        }
        """))

        #expect(mapped == .platform(LibraryScanPlatform(
            id: 3,
            name: "Super Nintendo",
            displayName: "SNES",
            slug: "snes",
            isIdentified: true,
            newFirmwareCount: 2
        )))
    }

    @Test func fallsBackThroughTheNamesAPlatformMightNotHave() {
        // Older servers leave display_name out, and an unidentified folder has
        // no name at all beyond its slug.
        let mapped = ScanEventMapper.map(event("scan:scanning_platform", #"{"id": 9, "slug": "gbc"}"#))

        #expect(mapped == .platform(LibraryScanPlatform(
            id: 9,
            name: "gbc",
            displayName: "gbc",
            slug: "gbc",
            isIdentified: false,
            newFirmwareCount: 0
        )))
    }

    @Test func aPlatformWithNothingToShowStillMaps() {
        let mapped = ScanEventMapper.map(event("scan:scanning_platform", "{}"))

        #expect(mapped == .platform(LibraryScanPlatform(
            id: 0,
            name: "Unknown platform",
            displayName: "Unknown platform",
            slug: "",
            isIdentified: false,
            newFirmwareCount: 0
        )))
    }

    // MARK: - ROMs

    @Test func mapsAScannedRom() {
        let mapped = ScanEventMapper.map(event("scan:scanning_rom", """
        {
          "id": 42,
          "name": "Sonic the Hedgehog",
          "fs_name": "sonic.md",
          "platform_name": "Mega Drive",
          "platform_slug": "genesis"
        }
        """))

        guard case .rom(let rom) = mapped else {
            Issue.record("Expected a ROM, got \(String(describing: mapped))")
            return
        }
        #expect(rom.romId == 42)
        #expect(rom.name == "Sonic the Hedgehog")
        #expect(rom.fileName == "sonic.md")
        #expect(rom.platformName == "Mega Drive")
    }

    @Test func anUnidentifiedRomFallsBackToItsFileNameAndPlatformSlug() {
        let mapped = ScanEventMapper.map(event("scan:scanning_rom", #"{"fs_name": "unknown.gb", "platform_slug": "gb"}"#))

        guard case .rom(let rom) = mapped else {
            Issue.record("Expected a ROM, got \(String(describing: mapped))")
            return
        }
        #expect(rom.romId == nil)
        #expect(rom.name == "unknown.gb")
        #expect(rom.platformName == "gb")
    }

    @Test func everyRomArrivalGetsItsOwnIdentity() {
        // The live feed is chronological, the same ROM can come in twice and
        // both rows have to survive in the list.
        let payload = #"{"id": 1, "name": "Tetris"}"#
        let first = ScanEventMapper.map(event("scan:scanning_rom", payload))
        let second = ScanEventMapper.map(event("scan:scanning_rom", payload))

        guard case .rom(let a) = first, case .rom(let b) = second else {
            Issue.record("Expected two ROMs")
            return
        }
        #expect(a.id != b.id)
        #expect(a.romId == b.romId)
    }

    // MARK: - Stats

    @Test func mapsTheStatsCounters() {
        let mapped = ScanEventMapper.map(event("scan:update_stats", """
        {
          "total_platforms": 4,
          "total_roms": 120,
          "scanned_platforms": 2,
          "new_platforms": 1,
          "identified_platforms": 2,
          "scanned_roms": 30,
          "new_roms": 5,
          "identified_roms": 28,
          "scanned_firmware": 3,
          "new_firmware": 1
        }
        """))

        #expect(mapped == .stats(LibraryScanStats(
            totalPlatforms: 4,
            totalRoms: 120,
            scannedPlatforms: 2,
            newPlatforms: 1,
            identifiedPlatforms: 2,
            scannedRoms: 30,
            newRoms: 5,
            identifiedRoms: 28,
            scannedFirmware: 3,
            newFirmware: 1
        )))
    }

    @Test func statsMissingACounterReadItAsZero() {
        let mapped = ScanEventMapper.map(event("scan:update_stats", #"{"scanned_roms": 7}"#))

        guard case .stats(let stats) = mapped else {
            Issue.record("Expected stats, got \(String(describing: mapped))")
            return
        }
        #expect(stats.scannedRoms == 7)
        #expect(stats.totalRoms == 0)
    }

    // MARK: - End of the run

    @Test func mapsTheDoneEventWithoutLookingAtItsPayload() {
        #expect(ScanEventMapper.map(event("scan:done", nil)) == .finished)
        #expect(ScanEventMapper.map(event("scan:done", #"{"anything": true}"#)) == .finished)
    }

    @Test func readsTheFailureReasonOutOfAJSONString() {
        let mapped = ScanEventMapper.map(event("scan:done_ko", #""A scan is already in progress""#))
        #expect(mapped == .failed("A scan is already in progress"))
    }

    @Test func readsAFailureReasonThatIsNotValidJSON() {
        #expect(ScanEventMapper.map(event("scan:done_ko", "Something broke")) == .failed("Something broke"))
    }

    @Test func aFailureWithoutAReasonStillSaysSomething() {
        #expect(ScanEventMapper.map(event("scan:done_ko", nil)) == .failed("The scan failed."))
        #expect(ScanEventMapper.map(event("scan:done_ko", #""""#)) == .failed("The scan failed."))
    }

    // MARK: - Everything else

    @Test func dropsEventsTheLiveViewDoesNotConsume() {
        #expect(ScanEventMapper.map(event("scan:scanning_firmware", "{}")) == nil)
        #expect(ScanEventMapper.map(event("connect", nil)) == nil)
    }

    @Test func dropsAKnownEventWhosePayloadDoesNotDecode() {
        #expect(ScanEventMapper.map(event("scan:scanning_platform", nil)) == nil)
        #expect(ScanEventMapper.map(event("scan:update_stats", #""not an object""#)) == nil)
    }
}
