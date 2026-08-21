import SwiftUI

/// A ROM whose engine is already resolved, waiting for the user's resume choice.
private struct PendingLaunch: Identifiable {
    let rom: DownloadedROM
    let decision: LaunchDecision

    var id: Int { rom.id }
}

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
    /// ROM awaiting a resume/new-game choice in the pre-launch sheet, together
    /// with the engine already resolved for it.
    @State private var romPendingLaunch: PendingLaunch?
    /// Slot chosen in the pre-launch sheet; read by the emulator cover builder.
    @State private var pendingResumeSlot: Int?
    private let factory: PDependencyFactory
    private let launchUseCase: PLaunchEmulatorUseCase
    private let updateLastPlayedUseCase: PUpdateLastPlayedUseCase
    private let saveStore: PSaveStore

    init(platformName: String, viewModel: LocalDeviceDetailViewModel, onDelete: @escaping (DownloadedROM) -> Void, factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.platformName = platformName
        self.viewModel = viewModel
        self.onDelete = onDelete
        self.factory = factory
        self.launchUseCase = factory.makeLaunchEmulatorUseCase()
        self.updateLastPlayedUseCase = factory.makeUpdateLastPlayedUseCase()
        self.saveStore = factory.saveStore
    }

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
                    lastSync: viewModel.lastSync(romId: rom.id),
                    onPlay: {
                        guard isPlatformSupported(rom.platformSlug), launchingRomId == nil else { return }
                        launchingRomId = rom.id
                        Task { await startPlay(rom: rom) }
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
            pendingResumeSlot = nil
            OrientationLock.set(.portrait, rotateTo: .portrait)
        }) { decision in
            EmulatorRouterView(decision: decision, resumeSlot: pendingResumeSlot)
                .ignoresSafeArea()
        }
        .sheet(item: $romPendingLaunch) { pending in
            PreLaunchSheet(
                romName: pending.rom.name,
                romId: pending.rom.id,
                saveStore: saveStore
            ) { resumeSlot in
                romPendingLaunch = nil
                launchingRomId = pending.rom.id
                present(pending.decision, rom: pending.rom, resumeSlot: resumeSlot)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            SyncSaveSheet(viewModel: factory.makeSyncSaveViewModel(rom: rom)) { romPendingSync = nil }
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

    /// Resolves the engine before anything is shown: only local cores can load a
    /// save state, so a ROM that boots into the web emulator skips the resume
    /// choice and goes straight into a fresh session.
    private func startPlay(rom: DownloadedROM) async {
        let start = Date()
        let result = await launchUseCase.execute(rom: rom.toRom())
        guard case .success(let decision) = result else {
            launchingRomId = nil
            return
        }

        if decision.supportsSaveStates, hasSaveState(romId: rom.id) {
            launchingRomId = nil
            romPendingLaunch = PendingLaunch(rom: rom, decision: decision)
            return
        }

        // Keep the card's spinner on screen long enough to read as feedback.
        let elapsed = Date().timeIntervalSince(start)
        let minVisible: TimeInterval = 0.45
        if elapsed < minVisible {
            try? await Task.sleep(nanoseconds: UInt64((minVisible - elapsed) * 1_000_000_000))
        }
        present(decision, rom: rom, resumeSlot: nil)
    }

    private func present(_ decision: LaunchDecision, rom: DownloadedROM, resumeSlot: Int?) {
        // Set the slot before the decision so the cover builder reads it.
        pendingResumeSlot = resumeSlot
        launchDecision = decision
        Task { [updateLastPlayedUseCase] in
            try? await updateLastPlayedUseCase.execute(romId: rom.id)
        }
    }

    private func isPlatformSupported(_ platformSlug: String) -> Bool {
        let supportedPlatforms: Set<String> = [
            "nes", "snes", "n64", "gba", "gbc", "gb", "nds",
            "genesis", "megadrive", "mastersystem", "gamegear", "saturn", "dreamcast",
            "sms", "master-system", "game-gear", "sg1000", "sg-1000", "segacd", "sega-cd", "mega-cd",
            "psx", "ps1", "playstation", "psp",
            "pce", "pc-engine", "pcengine", "turbografx", "tg16", "supergrafx",
            "arcade"
        ]
        return supportedPlatforms.contains { platformSlug.lowercased().contains($0) }
    }
}
