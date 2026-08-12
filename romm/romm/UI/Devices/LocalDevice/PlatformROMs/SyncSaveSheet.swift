import SwiftUI

enum PendingUpload: Equatable {
    case state(slot: Int, existingId: Int?)
    case battery(existingId: Int?)

    var title: String {
        switch self {
        case .state(let slot, _): return "Slot \(slot)"
        case .battery: return "Battery save"
        }
    }
    var hasExisting: Bool {
        switch self {
        case .state(_, let id): return id != nil
        case .battery(let id): return id != nil
        }
    }
}

struct SyncSaveSheet: View {
    @State var viewModel: SyncSaveViewModel
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingServer {
                    ProgressView("Loading cloud data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let meta = viewModel.lastSyncMeta {
                            syncStatusHeader(meta)
                        }
                        serverSection
                        localSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Sync Save Data")
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
            .confirmationDialog(
                "Already on Server",
                isPresented: Binding(
                    get: { viewModel.pendingUpload?.hasExisting == true },
                    set: { if !$0 { viewModel.cancelPendingUpload() } }
                ),
                titleVisibility: .visible
            ) {
                Button("Update existing") { viewModel.confirmUpload(update: true) }
                Button("Add as new") { viewModel.confirmUpload(update: false) }
                Button("Cancel", role: .cancel) { viewModel.cancelPendingUpload() }
            } message: {
                Text("\"\(viewModel.pendingUpload?.title ?? "")\" already exists on the server. Update it or add as a new entry?")
            }
        }
        .task { await viewModel.loadAll() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func syncStatusHeader(_ meta: SyncMetadata) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(meta.trigger == .automatic ? .green : .orange)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last synced \(SyncSaveSheet.relativeString(meta.date))")
                        .font(.subheadline.weight(.semibold))
                    Text(meta.trigger == .automatic ? "Automatic, on launch or save" : "Manual sync")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    static func relativeString(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    @ViewBuilder
    private var serverSection: some View {
        Section {
            if viewModel.serverStates.isEmpty && viewModel.serverSaves.isEmpty {
                Text("No data on server")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.serverStates) { state in
                    syncRow(
                        icon: "bookmark.fill", tint: .purple,
                        label: state.fileNameNoExt,
                        date: state.updatedAt,
                        sizeBytes: state.fileSizeBytes,
                        isBusy: viewModel.downloadingStateIds.contains(state.id),
                        actionIcon: "arrow.down.circle.fill",
                        action: { viewModel.downloadServerState(state) }
                    )
                }
                ForEach(viewModel.serverSaves) { save in
                    syncRow(
                        icon: "memorychip", tint: .blue,
                        label: save.fileNameNoExt,
                        date: save.updatedAt,
                        sizeBytes: save.fileSizeBytes,
                        isBusy: viewModel.downloadingSaveIds.contains(save.id),
                        actionIcon: "arrow.down.circle.fill",
                        action: { viewModel.downloadServerSave(save) }
                    )
                }
            }
        } header: {
            Label("On Server", systemImage: "icloud.fill")
        }
    }

    @ViewBuilder
    private var localSection: some View {
        Section {
            if viewModel.localStates.isEmpty && !viewModel.hasLocalBattery {
                Text("No local saves or states")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.localStates) { entry in
                    syncRow(
                        icon: "bookmark.fill", tint: .purple,
                        label: "Slot \(entry.slot)",
                        date: entry.modifiedAt,
                        sizeBytes: nil,
                        isBusy: viewModel.uploadingStateSlots.contains(entry.slot),
                        actionIcon: "icloud.and.arrow.up",
                        action: { viewModel.uploadLocalState(entry: entry) }
                    )
                }
                if viewModel.hasLocalBattery {
                    syncRow(
                        icon: "memorychip", tint: .blue,
                        label: "Battery save",
                        date: viewModel.localBatteryDate,
                        sizeBytes: nil,
                        isBusy: viewModel.isUploadingBattery,
                        actionIcon: "icloud.and.arrow.up",
                        action: { viewModel.uploadLocalBattery() }
                    )
                }
            }
        } header: {
            Label("On Device", systemImage: "iphone")
        }
    }

    // MARK: - Row helper

    private func syncRow(icon: String, tint: Color, label: String, date: Date?, sizeBytes: Int?, isBusy: Bool, actionIcon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let date {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isBusy {
                ProgressView().scaleEffect(0.8)
            } else {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
