//
//  DownloadProgressLabelTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

/// The label under the download bar. It has to survive an unknown size, which
/// is the normal case whenever the server builds the archive on the fly and
/// announces no Content-Length.
struct DownloadProgressLabelTests {

    @Test func showsPercentageAndRateWhenBothKnown() {
        let label = DownloadTask.progressLabel(progress: 0.42, bytesPerSecond: 3_200_000)
        #expect(label.hasPrefix("42%"))
        #expect(label.contains("/s"))
    }

    @Test func fallsBackToWordingWhenSizeIsUnknown() {
        let label = DownloadTask.progressLabel(progress: nil, bytesPerSecond: 1_000_000)
        #expect(label.hasPrefix("Downloading"))
        #expect(label.contains("/s"))
    }

    @Test func omitsRateUntilOneHasBeenMeasured() {
        #expect(DownloadTask.progressLabel(progress: 0.5, bytesPerSecond: nil) == "50%")
        #expect(DownloadTask.progressLabel(progress: nil, bytesPerSecond: nil) == "Downloading…")
    }

    /// A rate of zero means "nothing measured yet", not "stalled at 0 B/s".
    @Test func treatsAZeroRateAsUnmeasured() {
        #expect(DownloadTask.formattedRate(0) == nil)
        #expect(DownloadTask.formattedRate(nil) == nil)
        #expect(DownloadTask.formattedRate(1_500_000) != nil)
    }

    @Test func roundsRatherThanTruncatingThePercentage() {
        // 0.999 is not finished yet, but it should not read as 99% either.
        #expect(DownloadTask.progressLabel(progress: 0.999, bytesPerSecond: nil) == "100%")
        #expect(DownloadTask.progressLabel(progress: 0.005, bytesPerSecond: nil) == "1%")
    }
}
