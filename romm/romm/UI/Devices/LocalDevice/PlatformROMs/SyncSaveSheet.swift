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
    let rom: DownloadedROM
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var serverStates: [StateSchema] = []
    @State private var serverSaves: [SaveSchema] = []
    @State private var localStates: [SaveStateEntry] = []
    @State private var hasLocalBattery: Bool = false
    @State private var localBatteryDate: Date? = nil
    @State private var isLoadingServer: Bool = false
    @State private var downloadingStateIds: Set<Int> = []
    @State private var downloadingSaveIds: Set<Int> = []
    @State private var uploadingStateSlots: Set<Int> = []
    @State private var isUploadingBattery: Bool = false
    @State private var errorMessage: String? = nil
    @State private var pendingUpload: PendingUpload? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingServer {
                    ProgressView("Loading cloud data…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
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
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Already on Server",
                isPresented: Binding(get: { pendingUpload?.hasExisting == true }, set: { if !$0 { pendingUpload = nil } }),
                titleVisibility: .visible
            ) {
                Button("Update existing") {
                    if let p = pendingUpload { executeUpload(p, update: true) }
                    pendingUpload = nil
                }
                Button("Add as new") {
                    if let p = pendingUpload { executeUpload(p, update: false) }
                    pendingUpload = nil
                }
                Button("Cancel", role: .cancel) { pendingUpload = nil }
            } message: {
                Text("\"\(pendingUpload?.title ?? "")\" already exists on the server. Update it or add as a new entry?")
            }
        }
        .task { await loadAll() }
    }

    // MARK: - Load

    private func loadAll() async {
        isLoadingServer = true
        let api = RommAPIClient.shared
        do {
            async let statesTask = api.getStates(romId: rom.id)
            async let savesTask = api.getSaves(romId: rom.id)
            let (states, saves) = try await (statesTask, savesTask)
            serverStates = states
            serverSaves = saves
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingServer = false
        let store = DefaultDependencyFactory.shared.saveStore
        localStates = (try? store.listStates(romId: rom.id)) ?? []
        localBatteryDate = store.batteryModifiedAt(romId: rom.id)
        hasLocalBattery = localBatteryDate != nil
    }

    // MARK: - Download

    private func downloadState(_ state: StateSchema) {
        guard !downloadingStateIds.contains(state.id) else { return }
        if state.missingFromFs {
            errorMessage = "File missing on server — upload it again."
            return
        }
        downloadingStateIds.insert(state.id)
        Task { @MainActor in
            defer { downloadingStateIds.remove(state.id) }
            do {
                let data = try await RommAPIClient.shared.getBinary(state.downloadPath)
                guard !data.isEmpty else {
                    errorMessage = "Server returned empty file."
                    return
                }
                let slot = slotFromFileName(state.fileName) ?? 0
                let store = DefaultDependencyFactory.shared.saveStore
                try store.writeState(romId: rom.id, slot: slot, data: data)
                localStates = (try? store.listStates(romId: rom.id)) ?? []
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func downloadSave(_ save: SaveSchema) {
        guard !downloadingSaveIds.contains(save.id) else { return }
        if save.missingFromFs {
            errorMessage = "File missing on server — upload it again."
            return
        }
        downloadingSaveIds.insert(save.id)
        Task { @MainActor in
            defer { downloadingSaveIds.remove(save.id) }
            do {
                let data = try await RommAPIClient.shared.getBinary(save.downloadPath)
                guard !data.isEmpty else {
                    errorMessage = "Server returned empty file."
                    return
                }
                let store = DefaultDependencyFactory.shared.saveStore
                try store.writeBattery(romId: rom.id, data: data)
                hasLocalBattery = true
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Upload trigger

    private func uploadLocalState(entry: SaveStateEntry) {
        let existingId = serverStates.first { slotFromFileName($0.fileName) == entry.slot }?.id
        let pending = PendingUpload.state(slot: entry.slot, existingId: existingId)
        if existingId != nil {
            pendingUpload = pending
        } else {
            executeUpload(pending, update: false)
        }
    }

    private func uploadLocalBattery() {
        let existingId = serverSaves.first?.id
        let pending = PendingUpload.battery(existingId: existingId)
        if existingId != nil {
            pendingUpload = pending
        } else {
            executeUpload(pending, update: false)
        }
    }

    private func executeUpload(_ pending: PendingUpload, update: Bool) {
        let factory = DefaultDependencyFactory.shared
        switch pending {
        case .state(let slot, let existingId):
            uploadingStateSlots.insert(slot)
            Task { @MainActor in
                defer { uploadingStateSlots.remove(slot) }
                do {
                    let store = factory.saveStore
                    guard let data = try store.readState(romId: rom.id, slot: slot) else { return }
                    let thumbnail = try? store.readThumbnail(romId: rom.id, slot: slot)
                    let fileName = "slot\(slot).state"
                    let repo = factory.statesRepository
                    if update, let existingId {
                        let updated = try await UpdateStateUseCase(repository: repo).execute(id: existingId, emulator: nil, fileName: fileName, fileData: data, screenshotData: thumbnail)
                        if let idx = serverStates.firstIndex(where: { $0.id == updated.id }) { serverStates[idx] = updated }
                    } else {
                        let uploaded = try await UploadStateUseCase(repository: repo).execute(romId: rom.id, emulator: nil, fileName: fileName, fileData: data, screenshotData: thumbnail)
                        serverStates.append(uploaded)
                    }
                } catch {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        case .battery(let existingId):
            isUploadingBattery = true
            Task { @MainActor in
                defer { isUploadingBattery = false }
                do {
                    let store = factory.saveStore
                    guard let data = try store.readBattery(romId: rom.id) else { return }
                    let fileName = "\(rom.id).sav"
                    let repo = factory.savesRepository
                    if update, let existingId {
                        let updated = try await UpdateSaveUseCase(repository: repo).execute(id: existingId, emulator: nil, fileName: fileName, fileData: data, screenshotData: nil)
                        if let idx = serverSaves.firstIndex(where: { $0.id == updated.id }) { serverSaves[idx] = updated }
                    } else {
                        let uploaded = try await UploadSaveUseCase(repository: repo).execute(romId: rom.id, emulator: nil, slot: nil, fileName: fileName, fileData: data, screenshotData: nil)
                        serverSaves.append(uploaded)
                    }
                } catch {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var serverSection: some View {
        Section {
            if serverStates.isEmpty && serverSaves.isEmpty {
                Text("No data on server")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(serverStates) { state in
                    syncRow(
                        icon: "bookmark.fill", tint: .purple,
                        label: state.fileNameNoExt,
                        date: state.updatedAt,
                        sizeBytes: state.fileSizeBytes,
                        isBusy: downloadingStateIds.contains(state.id),
                        actionIcon: "arrow.down.circle.fill",
                        action: { downloadState(state) }
                    )
                }
                ForEach(serverSaves) { save in
                    syncRow(
                        icon: "memorychip", tint: .blue,
                        label: save.fileNameNoExt,
                        date: save.updatedAt,
                        sizeBytes: save.fileSizeBytes,
                        isBusy: downloadingSaveIds.contains(save.id),
                        actionIcon: "arrow.down.circle.fill",
                        action: { downloadSave(save) }
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
            if localStates.isEmpty && !hasLocalBattery {
                Text("No local saves or states")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(localStates) { entry in
                    syncRow(
                        icon: "bookmark.fill", tint: .purple,
                        label: "Slot \(entry.slot)",
                        date: entry.modifiedAt,
                        sizeBytes: nil,
                        isBusy: uploadingStateSlots.contains(entry.slot),
                        actionIcon: "icloud.and.arrow.up",
                        action: { uploadLocalState(entry: entry) }
                    )
                }
                if hasLocalBattery {
                    syncRow(
                        icon: "memorychip", tint: .blue,
                        label: "Battery save",
                        date: localBatteryDate,
                        sizeBytes: nil,
                        isBusy: isUploadingBattery,
                        actionIcon: "icloud.and.arrow.up",
                        action: { uploadLocalBattery() }
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

    // MARK: - Helpers

    private func slotFromFileName(_ name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("slot") else { return nil }
        return Int(stem.dropFirst("slot".count))
    }
}
