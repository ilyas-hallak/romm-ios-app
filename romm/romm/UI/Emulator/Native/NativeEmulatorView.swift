import SwiftUI
import DeltaCore

struct NativeEmulatorView: View {
    @SwiftUI.State private var viewModel: NativeEmulatorViewModel
    @SwiftUI.State private var showMenu = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var screenBlanker = PhoneScreenBlanker.shared
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
            if screenBlanker.isBlanked {
                // Covers everything including the menu button, so the only way
                // out is the tap, which is also the most obvious one.
                Color.black
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { screenBlanker.noteActivity() }
                    .overlay(alignment: .bottom) {
                        Text("Tap to turn the screen back on")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.2))
                            .padding(.bottom, 40)
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.controlsHidden)
        .animation(.easeOut(duration: 0.25), value: viewModel.isLoading)
        .onChange(of: externalDisplay.isActive) { _, _ in updateAutoDim() }
        .onChange(of: viewModel.controlsHidden) { _, _ in updateAutoDim() }
        .onAppear {
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
            viewModel.bootstrap(resumeSlot: resumeSlot)
            viewModel.session?.onMenuRequested = { showMenu = true }
            // Only take over an external display while a game is on screen.
            ExternalDisplayManager.shared.beginSession()
            // Playing with a controller means nobody touches the phone, so auto
            // lock would otherwise background the app and stop emulation.
            UIApplication.shared.isIdleTimerDisabled = true
            updateAutoDim()
        }
        .onDisappear {
            viewModel.teardown()
            ExternalDisplayManager.shared.endSession()
            UIApplication.shared.isIdleTimerDisabled = false
            screenBlanker.setAutoDimAllowed(false)
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app must never strand the user with a dark panel.
            if phase != .active { screenBlanker.restore() }
            switch phase {
            case .active: viewModel.session?.resume()
            case .inactive, .background: viewModel.session?.pause()
            @unknown default: break
            }
        }
        .onChange(of: showMenu) { _, presented in
            if presented {
                viewModel.session?.pause()
                // The menu is touch operated, dimming underneath it would be absurd.
                screenBlanker.setAutoDimAllowed(false)
            } else {
                viewModel.session?.resume()
                updateAutoDim()
            }
        }
        .sheet(isPresented: $showMenu) {
            EmulatorMenuSheet(
                session: viewModel.session,
                onResume: { showMenu = false },
                onQuit: {
                    showMenu = false
                    dismiss()
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    /// Auto dimming is allowed exactly when the game is being shown on the TV and
    /// the touch controls are gone, which is the app's signal for "a physical
    /// controller is in use".
    private func updateAutoDim() {
        let allowed = externalDisplay.isActive && viewModel.controlsHidden && !showMenu
        screenBlanker.setAutoDimAllowed(allowed)
    }
}

private struct NativeGameViewControllerHost: UIViewControllerRepresentable {
    let controller: GameViewController
    func makeUIViewController(context: Context) -> GameViewController { controller }
    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {}
}

/// Standalone menu button shown in the top-trailing corner when the on-screen
/// touch controls are hidden (physical controller / Controller Mode "On"), so
/// the player can still reach the pause/save/quit menu.
struct EmulatorMenuButtonOverlay: View {
    let action: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: action) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .accessibilityLabel("Menu")
                .padding(.top, 6)
                .padding(.trailing, 12)
            }
            Spacer()
        }
    }
}
