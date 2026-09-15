//
//  TransferRateMeter.swift
//  romm
//

import Foundation

/// Measures transfer rate over a sliding 1-second window and throttles reporting
/// to at most once every 0.1 seconds.
///
/// A window rather than the average over the whole transfer, so a change in
/// speed still shows up in a large download. `now` is injected everywhere so a
/// test can drive it without waiting on a real clock.
struct TransferRateMeter {
    private let rateWindow: TimeInterval = 1.0
    private let reportInterval: TimeInterval = 0.1

    /// Nil until `start(at:)` opens the first window.
    private var windowStart: Date?
    private var windowStartBytes: Int64 = 0
    /// Rate of the last window that closed, nil until one has.
    private var currentRate: Double?
    private var lastReport: Date?

    /// Spelled out because the synthesized memberwise init is private to this
    /// file, its stored properties being private.
    init() {}

    /// Opens the first window. Nothing is measured before this.
    mutating func start(at now: Date) {
        windowStart = now
        windowStartBytes = 0
    }

    /// Takes the cumulative bytes of the whole transfer, not the bytes of the
    /// last chunk, and returns the rate of the last closed window. Nil while the
    /// first window is still open, and nil before `start(at:)`.
    mutating func record(totalBytes: Int64, at now: Date) -> Double? {
        guard let windowStart else { return nil }

        let elapsed = now.timeIntervalSince(windowStart)
        if elapsed >= rateWindow {
            currentRate = Double(totalBytes - windowStartBytes) / elapsed
            self.windowStart = now
            windowStartBytes = totalBytes
        }
        return currentRate
    }

    /// True at most once per `reportInterval`, and notes `now` as the last report
    /// whenever it says true.
    mutating func shouldReport(at now: Date) -> Bool {
        if let lastReport, now.timeIntervalSince(lastReport) < reportInterval {
            return false
        }
        lastReport = now
        return true
    }
}
