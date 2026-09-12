//
//  LibraryScanView.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  Read-only view of the running/last library scan (issue #160). Starting a
//  scan needs the server's Socket.IO endpoint, which this app does not speak
//  yet, so the sheet only ever shows status.
//

import SwiftUI

struct LibraryScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = LibraryScanViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library Scan")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onAppear {
                    if viewModel.scan == nil && !viewModel.isLoading {
                        Task {
                            await viewModel.load()
                        }
                    }
                }
                .onDisappear {
                    viewModel.cancelAllTasks()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.scan == nil {
            LoadingView("Loading scan status...", fillScreen: true)
        } else if let errorMessage = viewModel.errorMessage {
            errorStateView(message: errorMessage)
        } else if let scan = viewModel.scan {
            scanContentView(scan: scan)
        } else {
            emptyStateView
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func scanContentView(scan: LibraryScanStatus) -> some View {
        List {
            Section {
                statusHeader(scan: scan)
            }

            if let stats = scan.stats {
                Section {
                    statsGridSection(stats: stats)
                } header: {
                    Text("Scan Results")
                        .font(.headline)
                }
            }

            Section {
                footnoteView
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func statusHeader(scan: LibraryScanStatus) -> some View {
        switch scan.state {
        case .queued, .running:
            runningHeader(scan: scan)
        case .finished:
            completedHeader(scan: scan, tone: .success)
        case .failed:
            completedHeader(scan: scan, tone: .failure)
        case .stopped, .unknown:
            completedHeader(scan: scan, tone: .neutral)
        }
    }

    @ViewBuilder
    private func runningHeader(scan: LibraryScanStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: scan))
                        .font(.headline)
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let stats = scan.stats, stats.totalRoms > 0 {
                ProgressView(value: Double(stats.scannedRoms), total: Double(stats.totalRoms))
                Text("\(stats.scannedRoms) of \(stats.totalRoms) ROMs scanned")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let startedAt = scan.startedAt {
                Text("Started \(startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private enum HeaderTone {
        case success
        case failure
        case neutral
    }

    @ViewBuilder
    private func completedHeader(scan: LibraryScanStatus, tone: HeaderTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: tone == .failure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundColor(color(for: tone))
                Text(title(for: scan))
                    .font(.headline)
            }

            Text(tone == .failure ? "Scan failed" : "Completed")
                .font(.subheadline)
                .foregroundColor(color(for: tone))

            if let endedAt = scan.endedAt {
                Text(endedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let note = statusNote(scan: scan, tone: tone) {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// The server labels each run itself, e.g. "Quick Scan" or "Complete Scan".
    private func title(for scan: LibraryScanStatus) -> String {
        scan.name.isEmpty ? "Library Scan" : scan.name
    }

    private func color(for tone: HeaderTone) -> Color {
        switch tone {
        case .success: return .green
        case .failure: return .orange
        case .neutral: return .secondary
        }
    }

    @ViewBuilder
    private func statsGridSection(stats: LibraryScanStats) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCardView(icon: "gamecontroller", value: "\(stats.scannedPlatforms)", label: "Platforms Scanned")
                StatCardView(icon: "plus.circle", value: "\(stats.newPlatforms)", label: "New Platforms")
            }

            HStack(spacing: 12) {
                StatCardView(icon: "checkmark.circle", value: "\(stats.identifiedPlatforms)", label: "Identified Platforms")
                StatCardView(icon: "opticaldisc", value: "\(stats.scannedRoms)", label: "ROMs Scanned")
            }

            HStack(spacing: 12) {
                StatCardView(icon: "plus.circle", value: "\(stats.newRoms)", label: "New ROMs")
                StatCardView(icon: "checkmark.circle", value: "\(stats.identifiedRoms)", label: "Identified ROMs")
            }

            HStack(spacing: 12) {
                StatCardView(icon: "cpu", value: "\(stats.scannedFirmware)", label: "Firmware Scanned")
                StatCardView(icon: "plus.circle", value: "\(stats.newFirmware)", label: "New Firmware")
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .padding(.horizontal)
    }

    // MARK: - Empty / Error states

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Library Scan")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("No library scan has run yet.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            footnoteView
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func errorStateView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 80))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Could Not Load Scan Status")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Retry") {
                viewModel.retry()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var footnoteView: some View {
        Text("Scans can currently only be started from the RomM web UI.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Duration

    /// The server's own SCAN_TIMEOUT, after which a running scan is force-stopped.
    private static let serverScanTimeout: TimeInterval = 4 * 60 * 60

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func duration(scan: LibraryScanStatus) -> TimeInterval? {
        guard let startedAt = scan.startedAt, let endedAt = scan.endedAt else { return nil }
        let interval = endedAt.timeIntervalSince(startedAt)
        return interval > 0 ? interval : nil
    }

    private func statusNote(scan: LibraryScanStatus, tone: HeaderTone) -> String? {
        let duration = Self.duration(scan: scan)

        if tone == .failure {
            // The server's SCAN_TIMEOUT force-stops a scan after 4 hours. A
            // failed scan that ran close to that long almost certainly hit the
            // timeout rather than failing for any other reason, so it reads as
            // a normal, expected state rather than an app error.
            if let duration, duration >= Self.serverScanTimeout - (5 * 60) {
                return "Stopped after timeout, the server cancels scans after about 4 hours."
            }
            return nil
        }

        guard let duration, let durationText = Self.durationFormatter.string(from: duration) else {
            return nil
        }
        return "Took \(durationText)"
    }
}

#Preview {
    LibraryScanView()
}
