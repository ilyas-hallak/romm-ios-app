import SwiftUI

/// Shows list of ROMs for a specific platform
struct PlatformROMsListView: View {
    let platformName: String
    /// Read reactively from the parent's @Observable view model so the list
    /// updates after a delete — passing a snapshot `[DownloadedROM]` left the
    /// pushed detail view stuck on stale data while the parent reloaded.
    let viewModel: LocalDeviceDetailViewModel
    let onDelete: (DownloadedROM) -> Void

    private var roms: [DownloadedROM] {
        viewModel.romsByPlatform[platformName] ?? []
    }

    @State private var launchDecision: LaunchDecision?
    @State private var launchingRomId: Int?
    @State private var romPendingDelete: DownloadedROM?
    @State private var romPendingSync: DownloadedROM?
    @State private var detailRom: DownloadedROM?
    private let launchUseCase: PLaunchEmulatorUseCase = DefaultDependencyFactory.shared.makeLaunchEmulatorUseCase()
    private let updateLastPlayedUseCase: PUpdateLastPlayedUseCase = DefaultDependencyFactory.shared.makeUpdateLastPlayedUseCase()
    private let saveStore: PSaveStore = DefaultDependencyFactory.shared.saveStore

    var body: some View {
        List {
            ForEach(roms) { rom in
                ROMCardRow(
                    rom: rom,
                    isPlayable: isPlatformSupported(rom.platformSlug),
                    isLaunching: launchingRomId == rom.id,
                    isDisabled: launchingRomId != nil && launchingRomId != rom.id,
                    hasSaveGame: hasSaveGame(romId: rom.id),
                    hasSaveState: hasSaveState(romId: rom.id),
                    onPlay: {
                        if isPlatformSupported(rom.platformSlug) && launchingRomId == nil {
                            launchingRomId = rom.id
                            Task { await launch(rom: rom) }
                        }
                    },
                    onSync: { romPendingSync = rom },
                    onDetails: { detailRom = rom }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        romPendingDelete = rom
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    ShareSwipeButton(rom: rom)
                }
            }
        }
        .navigationTitle(viewModel.displayName(forPlatformName: platformName))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detailRom) { rom in
            RomDetailView(rom: rom.toRom())
        }
        .fullScreenCover(item: $launchDecision, onDismiss: {
            launchingRomId = nil
            OrientationLock.set(.portrait, rotateTo: .portrait)
        }) { decision in
            EmulatorRouterView(decision: decision)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Delete ROM?",
            isPresented: Binding(
                get: { romPendingDelete != nil },
                set: { if !$0 { romPendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: romPendingDelete
        ) { rom in
            Button("Delete \(rom.name)", role: .destructive) {
                onDelete(rom)
                romPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { romPendingDelete = nil }
        } message: { rom in
            Text("This will remove all files (\(rom.formattedSize)).")
        }
        .sheet(item: $romPendingSync) { rom in
            SyncSaveSheet(rom: rom) { romPendingSync = nil }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func hasSaveGame(romId: Int) -> Bool {
        saveStore.batteryModifiedAt(romId: romId) != nil
    }

    private func hasSaveState(romId: Int) -> Bool {
        if let states = try? saveStore.listStates(romId: romId), !states.isEmpty { return true }
        return false
    }

    private func launch(rom: DownloadedROM) async {
        let start = Date()
        let result = await launchUseCase.execute(rom: rom.toRom())
        let elapsed = Date().timeIntervalSince(start)
        let minVisible: TimeInterval = 0.45
        if elapsed < minVisible {
            try? await Task.sleep(nanoseconds: UInt64((minVisible - elapsed) * 1_000_000_000))
        }
        if case .success(let decision) = result {
            launchDecision = decision
            Task { [updateLastPlayedUseCase] in
                try? await updateLastPlayedUseCase.execute(romId: rom.id)
            }
        } else {
            launchingRomId = nil
        }
    }

    /// Check if platform is supported by EmulatorJS
    private func isPlatformSupported(_ platformSlug: String) -> Bool {
        let supportedPlatforms: Set<String> = [
            // Nintendo
            "nes", "snes", "n64", "gba", "gbc", "gb", "nds",
            // Sega
            "genesis", "megadrive", "mastersystem", "gamegear", "saturn", "dreamcast",
            // Sony
            "psx", "ps1", "playstation", "psp",
            // Other
            "arcade"
        ]

        return supportedPlatforms.contains { platformSlug.lowercased().contains($0) }
    }
}

/// Compact ROM card row with cover thumbnail, save indicator and action buttons.
private struct ROMCardRow: View {
    let rom: DownloadedROM
    let isPlayable: Bool
    let isLaunching: Bool
    let isDisabled: Bool
    let hasSaveGame: Bool
    let hasSaveState: Bool
    let onPlay: () -> Void
    let onSync: () -> Void
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CachedKFImage(urlString: rom.urlCover) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(rom.platformSlug)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                        .background(Color(.secondarySystemGroupedBackground))
                }
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(rom.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(rom.formattedSize)
                        Text("•")
                        Text(rom.formattedDate)
                        if rom.files.count > 1 {
                            Text("•")
                            Text("\(rom.files.count) files")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                    if hasSaveGame || hasSaveState {
                        HStack(spacing: 6) {
                            if hasSaveGame {
                                SaveBadge(icon: "memorychip", title: "Save game", tint: .blue)
                            }
                            if hasSaveState {
                                SaveBadge(icon: "bookmark.fill", title: "Save state", tint: .purple)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if isLaunching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                        Text("Launching")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color.green.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    CardActionButton(
                        title: "Play",
                        systemImage: "play.fill",
                        tint: .green,
                        filled: true,
                        action: onPlay
                    )
                    .disabled(!isPlayable || isDisabled)
                    .opacity((!isPlayable || isDisabled) ? 0.5 : 1)
                }

                Button(action: onDetails) {
                    CardActionLabel(title: "Details", systemImage: "info.circle", tint: .accentColor)
                }
                .buttonStyle(.plain)

                CardActionButton(
                    title: "Sync",
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: .accentColor,
                    filled: false,
                    action: onSync
                )
            }
        }
        .padding(.vertical, 4)
        .opacity(isLaunching ? 0.7 : 1)
    }
}

private struct SaveBadge: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(title)
                .font(.caption2.weight(.medium))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(tint.opacity(0.12))
        )
    }
}

private struct CardActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardActionLabel(title: title, systemImage: systemImage, tint: filled ? .white : tint, filled: filled, fillColor: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct CardActionLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    var filled: Bool = false
    var fillColor: Color = .clear

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundColor(tint)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(filled ? fillColor : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(filled ? Color.clear : tint.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - SyncSaveSheet

private enum PendingUpload: Equatable {
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

private struct SyncSaveSheet: View {
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

/// Share swipe action button
private struct ShareSwipeButton: View {
    let rom: DownloadedROM
    @State private var shareSheetItem: ShareSheetItem?
    @State private var showFileNotFoundAlert = false
    @State private var temporaryShareDirectory: URL?

    var body: some View {
        Button {
            let (files, tempDir) = getROMFiles()
            if files.isEmpty {
                showFileNotFoundAlert = true
            } else {
                temporaryShareDirectory = tempDir
                shareSheetItem = ShareSheetItem(urls: files)
                print("🎯 Created ShareSheetItem with \(files.count) URLs")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
        .sheet(item: $shareSheetItem, onDismiss: cleanupTemporaryFiles) { item in
            let _ = print("📋 Sheet presenting with \(item.urls.count) items:")
            let _ = item.urls.forEach { print("   - \($0.lastPathComponent)") }

            ShareSheet(activityItems: item.urls)
        }
        .alert("Files Not Found", isPresented: $showFileNotFoundAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The ROM files could not be found on this device. They may have been deleted or moved.")
        }
    }

    // MARK: - File Sharing Logic

    private func getROMFiles() -> (files: [URL], tempDirectory: URL?) {
        let romsBaseURL = LocalROMRepository().romsBaseURL
        let fileManager = FileManager.default
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

        let shareDirectory = tempDirectory.appendingPathComponent("ROMShare-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: shareDirectory, withIntermediateDirectories: true)

        var temporaryFileURLs: [URL] = []

        print("🔍 Searching for ROM files: \(rom.name)")
        print("   Stored path: \(rom.localDirectory)")

        var romDirectoryURL = romsBaseURL.appendingPathComponent(rom.localDirectory)

        if !fileManager.fileExists(atPath: romDirectoryURL.path) {
            print("⚠️ Stored path doesn't exist, searching all platforms...")
            if let actualPath = findActualROMPath(romsBaseURL: romsBaseURL, romName: rom.name, fileManager: fileManager) {
                romDirectoryURL = actualPath
                print("✅ Found ROM at: \(actualPath.path)")
            } else {
                print("❌ ROM directory not found anywhere")
                return ([], nil)
            }
        }

        for file in rom.files {
            let sourceURL = romDirectoryURL.appendingPathComponent(file.fileName)
            let destinationURL = shareDirectory.appendingPathComponent(file.fileName)

            if fileManager.fileExists(atPath: sourceURL.path) {
                do {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destinationURL.path)
                    temporaryFileURLs.append(destinationURL)
                    print("✅ Copied for sharing: \(file.fileName)")
                } catch {
                    print("❌ Failed to copy file for sharing: \(error)")
                }
            } else {
                print("⚠️ Source file doesn't exist: \(sourceURL.path)")
            }
        }

        if !temporaryFileURLs.isEmpty {
            print("📤 Prepared \(temporaryFileURLs.count) file(s) for sharing")
        }

        return (temporaryFileURLs, temporaryFileURLs.isEmpty ? nil : shareDirectory)
    }

    private func findActualROMPath(romsBaseURL: URL, romName: String, fileManager: FileManager) -> URL? {
        guard let platformDirs = try? fileManager.contentsOfDirectory(
            at: romsBaseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for platformDir in platformDirs {
            let romDir = platformDir.appendingPathComponent(romName)
            if fileManager.fileExists(atPath: romDir.path) {
                return romDir
            }
        }

        return nil
    }

    private func cleanupTemporaryFiles() {
        guard let tempDir = temporaryShareDirectory else { return }

        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: tempDir)
            print("🗑️ Cleaned up temporary share directory")
        } catch {
            print("⚠️ Failed to cleanup temporary files: \(error)")
        }

        temporaryShareDirectory = nil
        shareSheetItem = nil
    }
}

/// Identifiable wrapper for share sheet URLs
private struct ShareSheetItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}
