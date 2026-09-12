//
//  LibraryScanView.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  The library scan sheet (issue #160): the status of the last run, the live
//  view of a running one, and the controls to start and stop a scan.
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
                .safeAreaInset(edge: .bottom) {
                    actionBar
                }
                .sheet(isPresented: $viewModel.isShowingCredentialsPrompt) {
                    ScanCredentialsSheet(viewModel: viewModel)
                }
                .onAppear {
                    if viewModel.scan == nil && !viewModel.isLoading {
                        Task {
                            await viewModel.load()
                        }
                    }
                }
                .onDisappear {
                    // The server keeps scanning, this only closes the socket
                    // and stops polling.
                    viewModel.cancelAllTasks()
                }
        }
        .sheet(isPresented: $viewModel.isShowingStartSheet) {
            LibraryScanStartSheet(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.scan == nil && !viewModel.isLive {
            LoadingView("Loading scan status...", fillScreen: true)
        } else if let errorMessage = viewModel.errorMessage, !viewModel.isLive {
            errorStateView(message: errorMessage)
        } else {
            scanList
        }
    }

    // MARK: - List

    @ViewBuilder
    private var scanList: some View {
        List {
            if viewModel.isLive {
                Section {
                    LibraryScanLiveHeader(platform: viewModel.currentPlatform, stats: viewModel.liveStats)
                } header: {
                    Text("Running now")
                }
            }

            if let notice = viewModel.scanNotice {
                Section {
                    noticeView(notice)
                }
            }

            if let scan = viewModel.scan, !viewModel.isLive {
                Section {
                    statusHeader(scan: scan)
                } header: {
                    Text("Last scan")
                }
            }

            if let stats = displayedStats {
                Section {
                    LibraryScanStatsGrid(stats: stats)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                } header: {
                    Text(viewModel.isLive ? "Counters" : "Scan results")
                }
            }

            if !viewModel.recentRoms.isEmpty {
                Section {
                    ForEach(viewModel.recentRoms) { rom in
                        LibraryScanRomRow(rom: rom)
                    }
                } header: {
                    Text("ROMs found")
                } footer: {
                    Text("The most recent \(LibraryScanViewModel.liveRomLimit) ROMs of this run, newest first.")
                }
            }

            if viewModel.scan == nil && !viewModel.isLive && viewModel.scanNotice == nil {
                Section {
                    emptyStateView
                        .listRowBackground(Color.clear)
                }
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var displayedStats: LibraryScanStats? {
        viewModel.liveStats ?? viewModel.scan?.stats
    }

    // MARK: - Action bar

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                if viewModel.isScanRunning {
                    viewModel.stopScan()
                } else {
                    viewModel.showStartSheet()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isStarting || viewModel.isStopping {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: viewModel.isScanRunning ? "stop.fill" : "play.fill")
                    }
                    Text(actionTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(viewModel.isScanRunning ? .red : .blue)
            .disabled(viewModel.isStarting || viewModel.isStopping)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var actionTitle: String {
        if viewModel.isStarting { return "Starting..." }
        if viewModel.isStopping { return "Stopping..." }
        return viewModel.isScanRunning ? "Stop Scan" : "Start Scan"
    }

    // MARK: - Status

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
                    Text("Scanning, started elsewhere or earlier")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let stats = scan.stats, stats.totalRoms > 0 {
                ProgressView(value: Double(stats.scannedRoms), total: Double(stats.totalRoms))
                    .tint(.blue)
                Text("\(stats.scannedRoms) of \(stats.totalRoms) ROMs scanned")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            if let startedAt = scan.startedAt {
                Text("Started \(startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private enum HeaderTone {
        case success
        case failure
        case neutral
    }

    @ViewBuilder
    private func completedHeader(scan: LibraryScanStatus, tone: HeaderTone) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: tone == .failure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(color(for: tone))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: scan))
                        .font(.headline)

                    Text(tone == .failure ? "Scan failed" : "Completed")
                        .font(.caption)
                        .foregroundColor(color(for: tone))
                }

                Spacer(minLength: 0)
            }

            if let endedAt = scan.endedAt {
                Text(endedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let note = statusNote(scan: scan, tone: tone) {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
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

    // MARK: - Notices and states

    @ViewBuilder
    private func noticeView(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            Text(notice)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 44))
                .foregroundColor(.secondary)

            Text("No Library Scan")
                .font(.headline)

            Text("No scan has run yet. Start one to let the server pick up new files and metadata.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
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
