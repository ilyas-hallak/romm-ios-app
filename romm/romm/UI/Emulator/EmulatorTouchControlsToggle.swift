#if !APP_STORE
import SwiftUI

struct EmulatorTouchControlsToggle: View {
    enum Style {
        case settings
        case menu
    }

    @Binding private var alwaysShowTouchControls: Bool
    private let style: Style

    init(alwaysShowTouchControls: Binding<Bool>, style: Style = .menu) {
        self._alwaysShowTouchControls = alwaysShowTouchControls
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { alwaysShowTouchControls }, set: updatePreference)) {
                switch style {
                case .settings:
                    Text("Always show touch controls")
                case .menu:
                    Label("Always show touch controls", systemImage: "hand.tap")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .accessibilityIdentifier("emulator.alwaysShowTouchControls")
            if style == .menu {
                Text("Touch controls hide automatically when a controller is connected. Turn this on to keep them visible.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .onAppear(perform: synchronizePreference)
        .onReceive(NotificationCenter.default.publisher(for: .emulatorTouchControlsVisibilityChanged)) { _ in
            synchronizePreference()
        }
    }

    private func updatePreference(_ value: Bool) {
        // Placement rows in the parent follow this binding immediately.
        alwaysShowTouchControls = value
        EmulatorControllerState.alwaysShowTouchControls = value
    }

    private func synchronizePreference() {
        let current = EmulatorControllerState.alwaysShowTouchControls
        guard alwaysShowTouchControls != current else { return }
        alwaysShowTouchControls = current
    }
}
#endif
