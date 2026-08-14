import SwiftUI
import UIKit

struct LibretroEmulatorView: View {
    @SwiftUI.State private var viewModel: LibretroEmulatorViewModel
    @SwiftUI.State private var showMenu = false
    @SwiftUI.State private var isQuitting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private let resumeSlot: Int?

    init(rom: Rom, core: LibretroCore, resumeSlot: Int? = nil, factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.resumeSlot = resumeSlot
        let vm = factory.makeLibretroEmulatorViewModel(rom: rom, core: core)
        self._viewModel = SwiftUI.State(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session = viewModel.session, !viewModel.isLoading {
                LibretroHostView(viewController: session.viewController)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            if viewModel.isLoading {
                ProgressView("Loading \(viewModel.rom.name)…")
                    .foregroundStyle(.white)
            }
            if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("Libretro Error").font(.headline).foregroundStyle(.white)
                    Text(error).font(.caption).foregroundStyle(.white.opacity(0.7))
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            if viewModel.controlsHidden, !viewModel.isLoading, viewModel.errorMessage == nil {
                EmulatorMenuButtonOverlay { showMenu = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.controlsHidden)
        .animation(.easeOut(duration: 0.25), value: viewModel.isLoading)
        .onAppear {
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
            viewModel.onMenuRequested = { showMenu = true }
            viewModel.bootstrap(resumeSlot: resumeSlot)
        }
        .onDisappear { viewModel.teardown() }
        .onChange(of: scenePhase) { _, phase in
            // Gate on session presence: after teardown the session is nil,
            // and a stray .background firing here would otherwise reach the
            // singleton frontend with stale state.
            guard let session = viewModel.session else { return }
            switch phase {
            case .active: session.resume()
            case .inactive, .background: session.pause()
            @unknown default: break
            }
        }
        .onChange(of: showMenu) { _, presented in
            // Skip resume when the user is quitting — the emulator is about
            // to be torn down, kicking the core run-loop back to life would
            // race with dlclose().
            if presented {
                viewModel.session?.pause()
            } else if !isQuitting {
                viewModel.session?.resume()
            }
        }
        .sheet(isPresented: $showMenu) {
            LibretroMenuSheet(
                session: viewModel.session,
                aspectRatioPreference: viewModel.aspectRatioPreference,
                onResume: { showMenu = false },
                onQuit: {
                    isQuitting = true
                    showMenu = false
                    dismiss()
                }
            )
            .preferredColorScheme(.dark)
        }
    }
}

private struct LibretroMenuSheet: View {
    let session: LibretroSession?
    let aspectRatioPreference: PLibretroAspectRatioPreference
    let onResume: () -> Void
    let onQuit: () -> Void

    @SwiftUI.State private var selectedSlot: Int = 1
    @SwiftUI.State private var statusMessage: String?
    @SwiftUI.State private var refreshTick: Int = 0
    @SwiftUI.State private var showQuitConfirmation = false
    @SwiftUI.State private var aspectRatio: LibretroAspectRatio
    @SwiftUI.State private var hapticsOnRelease: Bool = HapticsPreferences.onRelease

    init(
        session: LibretroSession?,
        aspectRatioPreference: PLibretroAspectRatioPreference,
        onResume: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.session = session
        self.aspectRatioPreference = aspectRatioPreference
        self.onResume = onResume
        self.onQuit = onQuit
        self._aspectRatio = SwiftUI.State(initialValue: aspectRatioPreference.psx)
    }

    private let slots = Array(1...20)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        detailHeader
                        compactControls
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        actionButtons
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quit", role: .destructive) {
                        showQuitConfirmation = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onResume).bold()
                }
            }
            .alert(
                "Quit Game?",
                isPresented: $showQuitConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive, action: onQuit)
            } message: {
                Text("Unsaved progress will be lost.")
            }
        }
    }

    private var detailHeader: some View {
        VStack(spacing: 10) {
            previewArea
            HStack(spacing: 8) {
                if let date = session?.stateModifiedAt(slot: selectedSlot) {
                    Label(date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Label("Empty slot", systemImage: "tray")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                if session?.hasState(slot: selectedSlot) == true {
                    Circle().fill(.green).frame(width: 8, height: 8)
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .id(refreshTick)
    }

    private var compactControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Save Slot")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Menu {
                    Picker("Slot", selection: $selectedSlot) {
                        ForEach(slots, id: \.self) { slot in
                            let occupied = session?.hasState(slot: slot) == true
                            Text(occupied ? "Slot \(slot) •" : "Slot \(slot)").tag(slot)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Slot \(selectedSlot)")
                            .font(.body.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .foregroundColor(.white)
                }
            }
            HStack {
                Text("Aspect Ratio")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Picker("Aspect", selection: $aspectRatio) {
                    ForEach(LibretroAspectRatio.allCases) { ratio in
                        Text(ratio.displayName).tag(ratio)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .onChange(of: aspectRatio) { _, newValue in
                    aspectRatioPreference.psx = newValue
                    session?.reloadAspectRatio()
                }
            }
            HStack {
                Text("Release Haptics")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: $hapticsOnRelease)
                    .labelsHidden()
                    .onChange(of: hapticsOnRelease) { _, newValue in
                        HapticsPreferences.onRelease = newValue
                    }
            }
            if let preference = session?.screenPositionPreference,
               EmulatorControllerState.isConnected {
                EmulatorScreenControls(preference: preference) {
                    session?.reloadAspectRatio()
                }
            }
            #if DEBUG
            EmulatorControllerDebugToggle()
            #endif
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
            if let image = session?.thumbnail(slot: selectedSlot) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                    Text("No save state")
                        .font(.footnote)
                }
                .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(height: 180)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            stackedButton(
                title: "Load",
                icon: "tray.and.arrow.up",
                tint: .accentColor,
                filled: true,
                disabled: session?.hasState(slot: selectedSlot) != true
            ) {
                perform { try session?.loadState(slot: selectedSlot) }
                statusMessage = "Slot \(selectedSlot) loaded"
                onResume()
            }
            stackedButton(
                title: "Save",
                icon: "tray.and.arrow.down",
                tint: .accentColor,
                filled: false,
                disabled: false
            ) {
                perform { try session?.saveState(slot: selectedSlot) }
                statusMessage = "Slot \(selectedSlot) saved"
                refreshTick += 1
            }
            stackedButton(
                title: "Undo Save",
                icon: "arrow.uturn.backward",
                tint: .orange,
                filled: false,
                disabled: session?.hasUndoSave(slot: selectedSlot) != true
            ) {
                perform { try session?.undoSave(slot: selectedSlot) }
                statusMessage = "Save for slot \(selectedSlot) undone"
                refreshTick += 1
            }
            stackedButton(
                title: "Undo Load",
                icon: "arrow.uturn.backward.circle",
                tint: .orange,
                filled: false,
                disabled: session?.hasUndoLoad() != true
            ) {
                perform { try session?.undoLoad() }
                statusMessage = "Load undone"
                onResume()
            }
        }
    }

    @ViewBuilder
    private func stackedButton(
        title: String,
        icon: String,
        tint: Color,
        filled: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(filled ? .black : tint)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(filled ? tint : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(filled ? Color.clear : tint.opacity(0.4), lineWidth: 1)
            )
            .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
}

private struct LibretroHostView: UIViewControllerRepresentable {
    let viewController: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { viewController }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
