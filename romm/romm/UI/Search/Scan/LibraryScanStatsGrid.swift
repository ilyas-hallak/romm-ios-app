//
//  LibraryScanStatsGrid.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import SwiftUI

/// One counter of a scan. Deliberately flatter than `StatCardView`: eight of
/// these sit next to each other, so the value has to read at a glance without
/// the card taking over the screen.
///
/// Every tile takes the exact same height and keeps its label to one line.
/// A `minHeight` and a 2-line label still let a wrapped label grow its own
/// cell past its one-line row-mate, since `LazyVGrid` does not stretch cells
/// to match the tallest one in a row, so the longest label ("Identified
/// platforms") made its tile visibly bigger than the rest. A fixed height
/// plus `minimumScaleFactor` instead of wrapping is what actually guarantees
/// all eight read as one even grid.
struct ScanStatTile: View {
    static let height: CGFloat = 64

    let icon: String
    let value: Int
    let label: String
    var tint: Color = .blue

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .monospacedDigit()

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LibraryScanStatsGrid: View {
    let stats: LibraryScanStats

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ScanStatTile(icon: "gamecontroller", value: stats.scannedPlatforms, label: "Platforms scanned")
            ScanStatTile(icon: "plus.square.on.square", value: stats.newPlatforms, label: "New platforms", tint: .green)
            ScanStatTile(icon: "checkmark.seal", value: stats.identifiedPlatforms, label: "Identified platforms")
            ScanStatTile(icon: "opticaldisc", value: stats.scannedRoms, label: "ROMs scanned")
            ScanStatTile(icon: "sparkles", value: stats.newRoms, label: "New ROMs", tint: .green)
            ScanStatTile(icon: "checkmark.circle", value: stats.identifiedRoms, label: "Identified ROMs")
            ScanStatTile(icon: "cpu", value: stats.scannedFirmware, label: "Firmware scanned")
            ScanStatTile(icon: "plus.circle", value: stats.newFirmware, label: "New firmware", tint: .green)
        }
    }
}

#Preview {
    LibraryScanStatsGrid(
        stats: LibraryScanStats(
            totalPlatforms: 12,
            totalRoms: 6449,
            scannedPlatforms: 7,
            newPlatforms: 1,
            identifiedPlatforms: 6,
            scannedRoms: 2310,
            newRoms: 42,
            identifiedRoms: 2180,
            scannedFirmware: 9,
            newFirmware: 2
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
