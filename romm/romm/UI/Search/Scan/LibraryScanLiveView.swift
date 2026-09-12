//
//  LibraryScanLiveView.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  What the server reports while a scan is running: the platform it is on, the
//  ROMs as they come in, and the counters behind them.
//

import SwiftUI

struct LibraryScanLiveHeader: View {
    let platform: LibraryScanPlatform?
    let stats: LibraryScanStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform?.displayName ?? "Starting scan")
                        .font(.headline)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }

            if let stats, stats.totalRoms > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress(for: stats))
                        .tint(.blue)

                    HStack {
                        Text("\(stats.scannedRoms) of \(stats.totalRoms) ROMs")
                            .monospacedDigit()
                        Spacer()
                        Text("\(stats.scannedPlatforms) of \(stats.totalPlatforms) platforms")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        guard let platform else { return "Waiting for the server" }
        return platform.isIdentified ? "Scanning platform" : "Scanning platform, not identified"
    }

    private func progress(for stats: LibraryScanStats) -> Double {
        guard stats.totalRoms > 0 else { return 0 }
        return min(1, Double(stats.scannedRoms) / Double(stats.totalRoms))
    }
}

struct LibraryScanRomRow: View {
    let rom: LibraryScanRom

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(rom.name)
                    .font(.subheadline)
                    .lineLimit(1)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var detail: String? {
        let parts = [rom.platformName, rom.fileName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
}
