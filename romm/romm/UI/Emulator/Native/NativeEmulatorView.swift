import SwiftUI
import DeltaCore

struct NativeEmulatorView: View {
    @SwiftUI.State private var viewModel: NativeEmulatorViewModel
    @SwiftUI.State private var showMenu = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(rom: Rom, gameType: DeltaGameType, factory: PDependencyFactory = DefaultDependencyFactory.shared) {
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
        }
        .animation(.easeOut(duration: 0.25), value: viewModel.isLoading)
        .onAppear {
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
            viewModel.bootstrap()
            viewModel.session?.onMenuRequested = { showMenu = true }
        }
        .onDisappear {
            viewModel.teardown()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: viewModel.session?.resume()
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
}

private struct NativeGameViewControllerHost: UIViewControllerRepresentable {
    let controller: GameViewController
    func makeUIViewController(context: Context) -> GameViewController { controller }
    func updateUIViewController(_ uiViewController: GameViewController, context: Context) {}
}
