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
                if screenBlanker.isBlanked {
                    blankingOverlay
                }
            }
            .animation(.easeOut(duration: 0.2), value: screenBlanker.isBlanked)
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
            }
            .onDisappear {
                display.endSession()
                UIApplication.shared.isIdleTimerDisabled = false
                screenBlanker.setAutoDimAllowed(false)
            }
            .onChange(of: display.isActive) { _, _ in updateAutoDim() }
            .onChange(of: areTouchControlsHidden) { _, _ in updateAutoDim() }
            .onChange(of: isMenuOpen) { _, _ in updateAutoDim() }
            .onChange(of: scenePhase) { _, phase in
                // Leaving the app must never strand the user with a dark panel.
                if phase != .active { screenBlanker.restore() }
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
}
