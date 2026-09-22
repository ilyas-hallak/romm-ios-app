#if !APP_STORE
import SwiftUI
import DeltaCore

struct NativeEmulatorView: View {
    @SwiftUI.State private var viewModel: NativeEmulatorViewModel
    @SwiftUI.State private var showMenu = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Observed only to react to Phone as Controller's inputs (display
    /// connection, the preference toggle); `.playOnTV` below owns the rest of
    /// the external-display wiring.
    @ObservedObject private var externalDisplay = ExternalDisplayManager.shared

    private let resumeSlot: Int?

    init(rom: Rom, gameType: DeltaGameType, resumeSlot: Int? = nil, factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.resumeSlot = resumeSlot
        self._viewModel = SwiftUI.State(wrappedValue: NativeEmulatorViewModel(
            rom: rom, gameType: gameType,
            getDownloadedROM: factory.makeGetDownloadedROMUseCase(),
            resolveROMFile: factory.makeResolveROMFileUseCase(),
            saveStates: factory.makeEmulatorSaveStatesUseCase(),
            factory: factory
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session = viewModel.session, !viewModel.isLoading {
                NativeGameViewControllerHost(controller: session.viewController)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            if viewModel.isLoading {
                EmulatorLoadingOverlay(romName: viewModel.rom.name)
                    .transition(.opacity)
            }
            if let error = viewModel.errorMessage {
                EmulatorErrorOverlay(message: error) { dismiss() }
            }
            if viewModel.controlsHidden, !viewModel.isLoading, viewModel.errorMessage == nil {
                EmulatorMenuButtonOverlay { showMenu = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.controlsHidden)
        .animation(.easeOut(duration: 0.25), value: viewModel.isLoading)
        .playOnTV(areTouchControlsHidden: viewModel.controlsHidden, isMenuOpen: showMenu)
        .onAppear {
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
            viewModel.bootstrap(resumeSlot: resumeSlot)
            viewModel.session?.onMenuRequested = { showMenu = true }
            // Set the starting state outright. The `onChange` handlers below
            // only fire on a real transition, so a display that is already
            // active when the game starts would otherwise go unnoticed.
            viewModel.session?.updatePhoneVideoVisibility()
        }
        .onDisappear {
            viewModel.teardown()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                viewModel.session?.resume()
                // Re-assert the hidden state, a background trip can drop it.
                viewModel.session?.updatePhoneVideoVisibility()
            case .inactive, .background: viewModel.session?.pause()
            @unknown default: break
            }
        }
        .onChange(of: showMenu) { _, presented in
            if presented {
                viewModel.session?.pause()
            } else {
                viewModel.session?.resume()
            }
        }
        .onChange(of: externalDisplay.isActive) { _, _ in viewModel.session?.updatePhoneVideoVisibility() }
        .onChange(of: externalDisplay.isPhoneControllerOnlyEnabled) { _, _ in viewModel.session?.updatePhoneVideoVisibility() }
        .sheet(isPresented: $showMenu) {
            EmulatorMenuSheet(
                session: viewModel.session,
                faceButtonPreference: viewModel.gamepadFaceButtonPreference,
                menuShortcutPreference: viewModel.emulatorMenuShortcutPreference,
                onResume: { showMenu = false },
                onQuit: {
                    showMenu = false
                    dismiss()
                }
            )
            .preferredColorScheme(.dark)
        }
    }
}

private struct NativeGameViewControllerHost: UIViewControllerRepresentable {
    let controller: GameViewController
    func makeUIViewController(context: Context) -> GameViewController { controller }
    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {}
}
#endif
