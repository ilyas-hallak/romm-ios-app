import SwiftUI

/// Status over one ROM's sync, scoped down from the sync overview rather than
/// its own manual file manager: the same negotiate-and-run logic, the same
/// plan, just for this one game.
struct SyncSaveSheet: View {
    @State var viewModel: SyncSaveViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                switch viewModel.state {
                case .idle, .loading:
                    loadingSection
                case .failed(let error):
                    failureSection(error)
                case .loaded:
                    statusSection
                    syncSection
                }
                advancedSection
            }
            .navigationTitle(viewModel.rom.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(item: $viewModel.exportItem, onDismiss: { viewModel.cleanupExportTemp() }) { item in
                ShareSheet(activityItems: [item.url])
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.load()
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            batteryRow
            statesRow
        } header: {
            Text("Status")
        } footer: {
            if let meta = viewModel.lastSyncMeta {
                Text("Last synced \(meta.date.relativeAbbreviated()), "
                    + (meta.trigger == .automatic ? "automatic" : "manual"))
            }
        }
    }

    @ViewBuilder
    private var batteryRow: some View {
        switch viewModel.batteryStatus {
        case .inSync:
            statusRow(icon: "equal.circle.fill", tint: .secondary, title: "Battery Save", detail: Text("In sync"))
        case .willUpload:
            statusRow(icon: "arrow.up.circle.fill", tint: .blue, title: "Battery Save", detail: Text("Will upload"))
        case .willDownload:
            statusRow(icon: "arrow.down.circle.fill", tint: .green, title: "Battery Save", detail: Text("Will download"))
        case .conflict:
            statusRow(
                icon: "exclamationmark.triangle.fill", tint: .orange, title: "Battery Save", detail: Text("Conflict"),
                explanation: "Changed on this device and on the server since the last sync. Not synced for now."
            )
        case .noSaveYet:
            statusRow(icon: "icloud.slash", tint: .secondary, title: "Battery Save", detail: Text("No save yet"))
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statesRow: some View {
        switch viewModel.statesStatus {
        case .inSync:
            statusRow(icon: "equal.circle.fill", tint: .secondary, title: "Save States", detail: Text("In sync"))
        case .pending(let count):
            statusRow(
                icon: "arrow.up.arrow.down.circle.fill", tint: .blue, title: "Save States",
                detail: Text(statesPendingDetail(count: count))
            )
        case .unavailable:
            statusRow(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Save States", detail: Text("Could not check"))
        }
    }

    private func statesPendingDetail(count: Int) -> String {
        count == 1 ? String(localized: "1 state will sync") : String(localized: "\(count) states will sync")
    }

    private func statusRow(
        icon: String, tint: Color, title: LocalizedStringKey, detail: Text, explanation: LocalizedStringKey? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            detail
                .font(.callout)
                .foregroundStyle(tint == .secondary ? .secondary : tint)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Sync

    private var syncSection: some View {
        Section {
            Button {
                Task { await viewModel.syncThisGame() }
            } label: {
                HStack {
                    Spacer()
                    if viewModel.isSyncing {
                        ProgressView().padding(.trailing, 8)
                    }
                    Text("Sync This Game")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(!viewModel.canSync)
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

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            Button {
                viewModel.exportLocalBattery()
            } label: {
                Label("Export Local Battery Save", systemImage: "square.and.arrow.up")
            }
            Button {
                Task { await viewModel.exportServerBattery() }
            } label: {
                HStack {
                    Label("Export Server Battery Save", systemImage: "square.and.arrow.up")
                    if viewModel.isExportingServerSave {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isExportingServerSave)
        } header: {
            Text("Advanced")
        } footer: {
            Text("Saves a copy of the battery save as a .srm file you can share or move elsewhere.")
        }
    }

    // MARK: - Loading / failure

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
}
