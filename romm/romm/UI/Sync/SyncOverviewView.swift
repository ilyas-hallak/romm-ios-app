//
//  SyncOverviewView.swift
//  romm
//

import SwiftUI

/// One row per place saves live, each saying what a sync would do with it.
///
/// Read-only in both senses: it changes nothing on the server, and nothing
/// about the setup either. Granting a folder belongs to Settings › Emulator,
/// beside the app it concerns.
struct SyncOverviewView: View {
    @State private var viewModel: SyncOverviewViewModel

    init() {
        _viewModel = State(initialValue: SyncOverviewViewModel())
    }

    /// For previews, which need a view model already in a given state.
    init(viewModel: SyncOverviewViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            switch viewModel.state {
            case .idle, .loading:
                loadingSection
            case .failed(let error):
                failureSection(error)
            case .loaded(let preview):
                thisDeviceSection(preview)
            }
            externalAppsSection
        }
        .navigationTitle("Save Sync")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Check again")
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    // MARK: - This device

    private func thisDeviceSection(_ preview: SyncPreview) -> some View {
        // Not `reportedSaveCount`, which is every source together: another
        // app's saves are counted on its own row further down.
        let internalCount = preview.reportedCountsBySource[.internalStore] ?? 0
        return Section {
            NavigationLink {
                SyncPlanDetailView(viewModel: viewModel)
            } label: {
                sourceRow(
                    icon: "iphone",
                    title: String(localized: "This Device"),
                    subtitle: internalCount == 1
                        ? String(localized: "1 battery save reported")
                        : String(localized: "\(internalCount) battery saves reported"),
                    detail: preview.changeSummary ?? String(localized: "Up to date"),
                    isWarning: !preview.conflicts.isEmpty
                )
            }
            // A chevron into an empty list reads as a screen that failed.
            .disabled(preview.isUpToDate)
        } header: {
            Text("RomM")
        } footer: {
            // Nothing runs until the plan below is opened and "Sync Now" is
            // tapped: this row alone only asks the server what would change.
            Text("Nothing has been changed yet. Open this to review and run the "
                + "sync. Registered as device \(preview.deviceId).")
        }
    }

    // MARK: - External apps

    private var externalAppsSection: some View {
        Section {
            if viewModel.externalSources.isEmpty {
                Text("No emulator apps set up yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.externalSources, id: \.self) { emulator in
                    externalAppRow(emulator)
                }
            }
        } header: {
            Text("Emulator Apps")
        } footer: {
            Text("Read from and written to the folder set up for each app in "
                + "Settings › Emulator. A file a sync replaces there is kept as a backup.")
        }
    }

    @ViewBuilder
    private func externalAppRow(_ emulator: ExternalEmulatorID) -> some View {
        let title = emulator.emulator.displayName
        // Only meaningful once a preview is loaded: before that, there is
        // nothing yet to report a count from.
        let reportedCount = viewModel.preview?.reportedCountsBySource[.externalApp(emulator)] ?? 0
        if let scan = viewModel.externalScans[emulator] {
            NavigationLink {
                ExternalScanDetailView(scan: scan, romName: viewModel.displayName(forRom:))
            } label: {
                sourceRow(
                    icon: "gamecontroller",
                    title: title,
                    subtitle: reportedCount == 0 ? nil : reportedSavesSubtitle(reportedCount),
                    detail: scan.statusSummary,
                    isWarning: scan.matched.isEmpty
                )
            }
            .disabled(scan.isEmpty)
        } else {
            sourceRow(
                icon: "gamecontroller",
                title: title,
                subtitle: reportedCount == 0
                    ? String(localized: "No save folder set up")
                    : reportedSavesSubtitle(reportedCount),
                detail: "",
                isWarning: true
            )
        }
    }

    private func reportedSavesSubtitle(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 save reported")
            : String(localized: "\(count) saves reported")
    }

    // MARK: - Server states

    private var loadingSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Asking the server what would change…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failureSection(_ error: SyncPreviewError) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error.localizedDescription)
            }
        } header: {
            Text("Not Available")
        }
    }

    // MARK: - Shared row

    private func sourceRow(
        icon: String,
        title: String,
        subtitle: String?,
        detail: String,
        isWarning: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(isWarning ? Color.orange : .secondary)
            }
        }
    }
}

// MARK: - Previews


private func previewOperation(
    _ direction: SyncPreviewOperation.Direction,
    romId: Int,
    reason: String
) -> SyncPreviewOperation {
    SyncPreviewOperation(
        romId: romId,
        direction: direction,
        serverFileName: "Game [2026-09-04_22-01-15].sav",
        slot: SaveSlot.battery,
        emulator: nil,
        reason: reason,
        serverUpdatedAt: Date().addingTimeInterval(-7200)
    )
}

#Preview("A plan with changes") {
    NavigationStack {
        SyncOverviewView(viewModel: SyncOverviewViewModel(
            showing: .loaded(SyncPreview(
                deviceId: "ios-1",
                sessionId: 7,
                reportedSaveCount: 12,
                reportedCountsBySource: [.internalStore: 9, .externalApp(.delta): 3],
                operations: [
                    previewOperation(.upload, romId: 1, reason: "Newer on this device"),
                    previewOperation(.upload, romId: 2, reason: "Not on the server"),
                    previewOperation(.download, romId: 3, reason: "Newer on the server"),
                    previewOperation(.conflict, romId: 4, reason: "Both sides changed"),
                ]
            )),
            romNames: [1: "Chrono Trigger", 2: "Golden Sun", 3: "Metroid Fusion"]
        ))
    }
}

#Preview("Up to date") {
    NavigationStack {
        SyncOverviewView(viewModel: SyncOverviewViewModel(
            showing: .loaded(SyncPreview(
                deviceId: "ios-1",
                sessionId: nil,
                reportedSaveCount: 12,
                reportedCountsBySource: [.internalStore: 12],
                operations: []
            ))
        ))
    }
}

#Preview("Server too old") {
    NavigationStack {
        SyncOverviewView(viewModel: SyncOverviewViewModel(showing: .failed(.serverTooOld(version: "4.8.1"))))
    }
}

#Preview("Version unknown") {
    NavigationStack {
        SyncOverviewView(viewModel: SyncOverviewViewModel(showing: .failed(.serverVersionUnknown)))
    }
}

#Preview("Loading") {
    NavigationStack {
        SyncOverviewView(viewModel: SyncOverviewViewModel(showing: .loading))
    }
}
