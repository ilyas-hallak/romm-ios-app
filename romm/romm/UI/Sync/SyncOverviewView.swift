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
            if viewModel.preview != nil {
                syncNowSection
            }
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
                .disabled(viewModel.isLoading || viewModel.isSyncing)
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
        Section {
            NavigationLink {
                SyncPlanDetailView(preview: preview, romName: viewModel.displayName(forRom:))
            } label: {
                sourceRow(
                    icon: "iphone",
                    title: String(localized: "This Device"),
                    subtitle: preview.reportedSaveCount == 1
                        ? String(localized: "1 battery save reported")
                        : String(localized: "\(preview.reportedSaveCount) battery saves reported"),
                    detail: preview.changeSummary ?? String(localized: "Up to date"),
                    isWarning: !preview.conflicts.isEmpty
                )
            }
            // A chevron into an empty list reads as a screen that failed.
            .disabled(preview.isUpToDate)
        } header: {
            Text("RomM")
        } footer: {
            // Only a plan until "Sync Now" below is actually tapped.
            Text("Nothing has been changed yet. This is what tapping \"Sync Now\" "
                + "below would do. Registered as device \(preview.deviceId).")
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
            Text("Read from the folder set up for each app in Settings › Emulator. "
                + "Nothing is ever written to them; \"Sync Now\" below only uploads "
                + "a matched save when it is newer than what the server already has. "
                + "Each app says what the last run did with its saves.")
        }
    }

    // MARK: - Sync Now

    private var syncNowSection: some View {
        Section {
            Button {
                Task { await viewModel.syncNow() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSyncing {
                        ProgressView()
                            .padding(.trailing, 8)
                    }
                    Text("Sync Now")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(!viewModel.canSyncNow || viewModel.isSyncing)
        } footer: {
            if let summary = viewModel.lastSyncSummary {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary)
                    ForEach(viewModel.lastSyncErrors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func externalAppRow(_ emulator: ExternalEmulatorID) -> some View {
        let title = emulator.emulator.displayName
        if let scan = viewModel.externalScans[emulator] {
            // With saves to act on, what the last run did with them is the
            // news and the folder's own inventory moves below the name. With
            // none, that inventory is all there is to say.
            let hasSaves = !scan.matched.isEmpty
            NavigationLink {
                ExternalScanDetailView(scan: scan, romName: viewModel.displayName(forRom:))
            } label: {
                sourceRow(
                    icon: "gamecontroller",
                    title: title,
                    subtitle: hasSaves ? scan.statusSummary : nil,
                    detail: hasSaves ? viewModel.lastSyncDetail(for: emulator) : scan.statusSummary,
                    isWarning: !hasSaves || viewModel.lastSyncNeedsAttention(for: emulator)
                )
            }
            .disabled(scan.isEmpty)
        } else {
            sourceRow(
                icon: "gamecontroller",
                title: title,
                subtitle: String(localized: "No save folder set up"),
                detail: "",
                isWarning: true
            )
        }
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
                reportedSaveCount: 12,
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
            showing: .loaded(SyncPreview(deviceId: "ios-1", reportedSaveCount: 12, operations: []))
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
