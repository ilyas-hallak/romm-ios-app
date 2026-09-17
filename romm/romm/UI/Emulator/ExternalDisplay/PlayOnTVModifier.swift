import SwiftUI

extension View {

    /// Wires a running emulator screen into Play on TV: takes the display over
    /// for the duration of the session, keeps the device awake, and dims the
    /// handset once nobody is looking at it.
    ///
    /// Both emulator paths need exactly this, and had it copied verbatim.
    ///
    /// - Parameters:
    ///   - areTouchControlsHidden: The app's signal that a physical controller is
    ///     in use, since the skin is hidden precisely then.
    ///   - isMenuOpen: The in-game menu is touch operated, so it blocks dimming.
    func playOnTV(areTouchControlsHidden: Bool, isMenuOpen: Bool) -> some View {
        modifier(PlayOnTVModifier(
            areTouchControlsHidden: areTouchControlsHidden,
            isMenuOpen: isMenuOpen
        ))
    }
}

private struct PlayOnTVModifier: ViewModifier {

    let areTouchControlsHidden: Bool
    let isMenuOpen: Bool

    @ObservedObject private var display = ExternalDisplayManager.shared
    @ObservedObject private var screenBlanker = PhoneScreenBlanker.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPhoneVideoHidden {
                    playingOnTVBadge
                }
            }
            .overlay {
                if screenBlanker.isBlanked {
                    blankingOverlay
                }
            }
            .animation(.easeOut(duration: 0.2), value: screenBlanker.isBlanked)
            .animation(.easeOut(duration: 0.2), value: isPhoneVideoHidden)
            .onAppear {
                // Only take over an external display while a game is on screen.
                // Anchored in the SwiftUI view rather than a view controller
                // because presenting the menu sheet does not disturb this
                // lifecycle, while `viewDidDisappear` fires for it.
                display.beginSession()
                // Playing with a controller means nobody touches the phone, so
                // auto lock would otherwise background the app and stop emulation.
                UIApplication.shared.isIdleTimerDisabled = true
                updateAutoDim()
                // The engine views also set an orientation mask in their own
                // `.onAppear`, and SwiftUI does not guarantee which runs first.
                // Deferring by a runloop turn guarantees this one applies last.
                DispatchQueue.main.async { applyOrientationLock() }
            }
            .onDisappear {
                display.endSession()
                UIApplication.shared.isIdleTimerDisabled = false
                screenBlanker.setAutoDimAllowed(false)
            }
            .onChange(of: display.isActive) { _, _ in updateAutoDim() }
            .onChange(of: areTouchControlsHidden) { _, _ in updateAutoDim() }
            .onChange(of: isMenuOpen) { _, _ in updateAutoDim() }
            .onChange(of: isPhoneVideoHidden) { _, _ in applyOrientationLock() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    // Leaving the app must never strand the user with a dark panel.
                    screenBlanker.restore()
                } else {
                    // Nothing guarantees the lock survived a background trip
                    // (the system can reset orientation while the app is away),
                    // so re-assert it instead of trusting it stuck.
                    applyOrientationLock()
                }
            }
    }

    /// Covers everything including the menu button, so the only way out is the
    /// tap, which is also the most obvious one.
    private var blankingOverlay: some View {
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

    /// The engines hide their own picture themselves, but they leave the space it
    /// used behind. Without a word in it that gap reads as a broken screen.
    private var isPhoneVideoHidden: Bool {
        ExternalDisplayPolicy.shouldHidePhoneVideo(
            isRenderingExternally: display.isActive,
            isPhoneControllerOnlyEnabled: display.isPhoneControllerOnlyEnabled,
            areTouchControlsHidden: areTouchControlsHidden
        )
    }

    /// Sits in the middle, where neither layout puts a control, and never takes
    /// a touch away from the pad.
    private var playingOnTVBadge: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.system(size: 32, weight: .light))
            Text("Playing on TV")
                .font(.footnote)
        }
        .foregroundStyle(.white.opacity(0.22))
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func updateAutoDim() {
        screenBlanker.setAutoDimAllowed(
            ExternalDisplayPolicy.shouldAutoDimPhone(
                isRenderingExternally: display.isActive,
                areTouchControlsHidden: areTouchControlsHidden,
                isMenuOpen: isMenuOpen,
                isAutoDimPhoneEnabled: display.isAutoDimPhoneEnabled
            )
        )
    }

    /// While the phone is a pure controller the touch layout only reads as a
    /// gamepad in landscape, so portrait is locked out for that stretch.
    private func applyOrientationLock() {
        guard isPhoneVideoHidden else {
            OrientationLock.set([.portrait, .landscapeLeft, .landscapeRight])
            return
        }
        // A two-way mask alone does not reliably rotate a device sitting in
        // portrait, the same reason RomDetailView forces `rotateTo: .portrait`
        // rather than trusting a mask change on its own. A phone already held
        // sideways keeps the side it is on, forcing one would flip it out of the
        // player's hands.
        let isHeldSideways = OrientationLock.currentOrientation?.isLandscape ?? false
        OrientationLock.set(
            [.landscapeLeft, .landscapeRight],
            rotateTo: isHeldSideways ? nil : .landscapeRight
        )
    }
}
