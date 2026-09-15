//
//  TransferRateMeterTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct TransferRateMeterTests {

    @Test func returnsNilBeforeFirstWindowExpires() {
        var meter = TransferRateMeter()
        let now = Date()
        meter.start(at: now)

        let rate = meter.record(totalBytes: 1_000_000, at: now.addingTimeInterval(0.5))
        #expect(rate == nil)
    }

    @Test func returnsNilWhenNotStarted() {
        var meter = TransferRateMeter()
        let now = Date()

        // Never called start(), so windowStart is nil.
        let rate = meter.record(totalBytes: 1_000_000, at: now)
        #expect(rate == nil)
    }

    @Test func calculatesRateAfterWindowExpires() {
        var meter = TransferRateMeter()
        let t0 = Date()
        meter.start(at: t0)

        // At t=0.5s: 500_000 bytes
        meter.record(totalBytes: 500_000, at: t0.addingTimeInterval(0.5))

        // At t=1.0s: 1_000_000 bytes total, rate should be (1_000_000 - 0) / 1.0 = 1_000_000 B/s
        let rate = meter.record(totalBytes: 1_000_000, at: t0.addingTimeInterval(1.0))
        #expect(rate == 1_000_000)
    }

    @Test func rateReflectsTheCurrentWindow() {
        var meter = TransferRateMeter()
        let t0 = Date()
        meter.start(at: t0)

        // Fast phase: 2_000_000 bytes in 1 second.
        meter.record(totalBytes: 2_000_000, at: t0.addingTimeInterval(1.0))

        // Slow phase: 2_100_000 bytes total (only 100_000 in 1 second).
        let slowRate = meter.record(totalBytes: 2_100_000, at: t0.addingTimeInterval(2.0))

        // Rate should reflect only the slow phase, not the average.
        #expect(slowRate == 100_000)
    }

    @Test func throttlesReportsWithinInterval() {
        var meter = TransferRateMeter()
        let now = Date()

        // First report allowed.
        #expect(meter.shouldReport(at: now) == true)

        // Within 0.1 seconds: throttled.
        #expect(meter.shouldReport(at: now.addingTimeInterval(0.05)) == false)

        // Still within 0.1 seconds: throttled.
        #expect(meter.shouldReport(at: now.addingTimeInterval(0.09)) == false)

        // Exactly 0.1 seconds: allowed (boundary condition).
        #expect(meter.shouldReport(at: now.addingTimeInterval(0.1)) == true)

        // Soon after: throttled again.
        #expect(meter.shouldReport(at: now.addingTimeInterval(0.15)) == false)

        // Next interval allowed.
        #expect(meter.shouldReport(at: now.addingTimeInterval(0.2)) == true)
    }

    @Test func rateIsNilUntilFirstWindowClosedEvenWithVariableTiming() {
        var meter = TransferRateMeter()
        let t0 = Date()
        meter.start(at: t0)

        #expect(meter.record(totalBytes: 100_000, at: t0.addingTimeInterval(0.1)) == nil)
        #expect(meter.record(totalBytes: 500_000, at: t0.addingTimeInterval(0.5)) == nil)
        #expect(meter.record(totalBytes: 900_000, at: t0.addingTimeInterval(0.9)) == nil)

        // At exactly 1.0s, window closes.
        let rate = meter.record(totalBytes: 1_000_000, at: t0.addingTimeInterval(1.0))
        #expect(rate == 1_000_000)
    }

    @Test func handlesSlowDownloadWithVariableChunking() {
        var meter = TransferRateMeter()
        let t0 = Date()
        meter.start(at: t0)

        // Simulate irregular chunk arrival over first window.
        meter.record(totalBytes: 250_000, at: t0.addingTimeInterval(0.2))
        meter.record(totalBytes: 400_000, at: t0.addingTimeInterval(0.4))
        meter.record(totalBytes: 750_000, at: t0.addingTimeInterval(0.8))

        // At 1.0s: total 1_000_000 bytes, rate = 1_000_000 B/s
        let rate1 = meter.record(totalBytes: 1_000_000, at: t0.addingTimeInterval(1.0))
        #expect(rate1 == 1_000_000)

        // Second window: slow phase, only 200_000 bytes in 1 second
        meter.record(totalBytes: 1_100_000, at: t0.addingTimeInterval(1.5))
        let rate2 = meter.record(totalBytes: 1_200_000, at: t0.addingTimeInterval(2.0))
        #expect(rate2 == 200_000)
    }
}
