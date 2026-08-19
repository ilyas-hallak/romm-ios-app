import SwiftUI
import UIKit

struct LibretroEmulatorView: View {
    @SwiftUI.State private var viewModel: LibretroEmulatorViewModel
    @SwiftUI.State private var showMenu = false
    @SwiftUI.State private var isQuitting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var screenBlanker = PhoneScreenBlanker.shared
    #if DEBUG
    @SwiftUI.StateObject private var latencyProbe = LatencyProbe()
    #endif

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
            #if DEBUG
            latencyProbeOverlay
            #endif
            if screenBlanker.isBlanked {
                // Covers everything including the menu button, so the only way
                // out is the tap, which is also the most obvious one.
                Color.black
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { screenBlanker.restore() }
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
        .onAppear {
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
            viewModel.onMenuRequested = { showMenu = true }
            viewModel.bootstrap(resumeSlot: resumeSlot)
            // Only take over an external display while a game is on screen.
            // Anchored here rather than in the view controller because a sheet
            // does not disturb this view's lifecycle.
            ExternalDisplayManager.shared.beginSession()
            // Playing with a controller means nobody touches the phone, so auto
            // lock would otherwise background the app and stop emulation.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            viewModel.teardown()
            ExternalDisplayManager.shared.endSession()
            UIApplication.shared.isIdleTimerDisabled = false
            screenBlanker.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app must never strand the user with a dark panel.
            if phase != .active { screenBlanker.restore() }
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
                },
                onMeasureLatency: {
                    #if DEBUG
                    showMenu = false
                    startLatencyProbe()
                    #endif
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    #if DEBUG
    /// Sits on top of the game and collects the taps. Deliberately almost
    /// transparent: the flash has to stay clearly visible, it is what the player
    /// is reacting to.
    @ViewBuilder
    private var latencyProbeOverlay: some View {
        if latencyProbe.phase != .idle {
            VStack {
                Spacer()
                Text(latencyProbe.instruction)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                if !latencyProbe.isRunning {
                    Button("Done") { stopLatencyProbe() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                }
                Spacer().frame(height: 60)
            }
            .contentShape(Rectangle())
            .onTapGesture { latencyProbe.tapped() }
        }
    }

    private func startLatencyProbe() {
        latencyProbe.start()
        viewModel.session?.setLatencyFlashTest(true) {
            latencyProbe.flashDidShow()
        }
    }

    private func stopLatencyProbe() {
        viewModel.session?.setLatencyFlashTest(false)
        latencyProbe.cancel()
    }
    #endif
}

private struct LibretroMenuSheet: View {
    let session: LibretroSession?
    let aspectRatioPreference: PLibretroAspectRatioPreference
    let onResume: () -> Void
    let onQuit: () -> Void
    /// Closes the menu and hands control to the latency probe overlay. Only
    /// wired up in debug builds, where the measuring UI exists.
    var onMeasureLatency: () -> Void = {}

    @SwiftUI.State private var selectedSlot: Int
    @SwiftUI.State private var statusMessage: String?
    @SwiftUI.State private var refreshTick: Int = 0
    @SwiftUI.State private var showQuitConfirmation = false
    @SwiftUI.State private var aspectRatio: LibretroAspectRatio
    @SwiftUI.State private var hapticsOnRelease: Bool = HapticsPreferences.onRelease
    #if DEBUG
    @SwiftUI.State private var latencyFlashOn = false
    #endif

    // 0-based to match the save-state storage / cloud-sync layer
    // (files are `slot0.state`…`slot20.state`); slot 0 is a real, usable slot.
    private let slots = Array(0...20)

    init(
        session: LibretroSession?,
        aspectRatioPreference: PLibretroAspectRatioPreference,
        onResume: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onMeasureLatency: @escaping () -> Void = {}
    ) {
        self.session = session
        self.aspectRatioPreference = aspectRatioPreference
        self.onResume = onResume
        self.onQuit = onQuit
        self.onMeasureLatency = onMeasureLatency
        self._aspectRatio = SwiftUI.State(initialValue: aspectRatioPreference.psx)
        // Pre-select the most recently touched slot so existing saves are
        // immediately visible and loadable after the 1→0 slot renumbering (PR #57).
        let slots = Array(0...20)
        let mostRecent = slots.compactMap { slot -> (slot: Int, date: Date)? in
            guard let date = session?.stateModifiedAt(slot: slot) else { return nil }
            return (slot, date)
        }.max(by: { $0.date < $1.date })?.slot ?? 0
        self._selectedSlot = SwiftUI.State(initialValue: mostRecent)
    }

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
            ExternalDisplayControls(onRequestDismiss: onResume)
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
            latencyFlashToggle
            #endif
        }
    }

    #if DEBUG
    /// Flashes the picture white every two seconds so the phone and the TV can be
    /// filmed together in slow motion, and the frames between the two flashes
    /// counted. Rides the same layer as the game, so it measures the real path.
    private var latencyFlashToggle: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Latency Flash Test")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: $latencyFlashOn)
                    .labelsHidden()
                    .onChange(of: latencyFlashOn) { _, newValue in
                        session?.setLatencyFlashTest(newValue)
                    }
            }
            Text("Whites out the picture every 2s. Film both screens at 240fps and count frames.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
            Button("Measure AirPlay latency") {
                onMeasureLatency()
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundColor(.white)
            Text("No camera needed. You tap on the flashes twice, once watching the phone and once the TV, and the difference is the AirPlay delay.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

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
