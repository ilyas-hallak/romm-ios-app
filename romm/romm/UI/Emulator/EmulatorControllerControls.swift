import SwiftUI

/// Controller settings the player can reach without leaving the game, styled for
/// the dark in-game menus.
///
/// The same switches stay in Settings. They are repeated here because a
/// mirrored A/B pair is only noticed once a game is running, and walking out of
/// the game to fix it is the annoying part.
///
/// Only meaningful with a physical controller connected, which the caller
/// decides, same as it does for `EmulatorScreenControls`.
struct EmulatorControllerControls: View {
    let faceButtonPreference: PGamepadFaceButtonPreference
    /// `nil` hides the shortcut picker. The native engine opens its menu through
    /// DeltaCore's own menu input and never evaluates the combo, so offering it
    /// there would be a setting without an effect.
    let menuShortcutPreference: PEmulatorMenuShortcutPreference?
    /// Called after a change so the running session can re-apply it live.
    var onChange: () -> Void = {}

    @SwiftUI.State private var swapFaceButtons: Bool
    @SwiftUI.State private var menuShortcut: EmulatorMenuShortcut

    init(
        faceButtonPreference: PGamepadFaceButtonPreference,
        menuShortcutPreference: PEmulatorMenuShortcutPreference? = nil,
        onChange: @escaping () -> Void = {}
    ) {
        self.faceButtonPreference = faceButtonPreference
        self.menuShortcutPreference = menuShortcutPreference
        self.onChange = onChange
        self._swapFaceButtons = SwiftUI.State(initialValue: faceButtonPreference.isSwapped)
        self._menuShortcut = SwiftUI.State(initialValue: menuShortcutPreference?.current ?? .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controller")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            HStack {
                Text("Swap A/B and X/Y")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Toggle("", isOn: $swapFaceButtons)
                    .labelsHidden()
                    .onChange(of: swapFaceButtons) { _, newValue in
                        faceButtonPreference.isSwapped = newValue
                        onChange()
                    }
            }
            if let menuShortcutPreference {
                HStack {
                    Text("Menu shortcut")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Picker("Menu shortcut", selection: $menuShortcut) {
                        Text("Off").tag(EmulatorMenuShortcut.none)
                        Text("L3 + R3").tag(EmulatorMenuShortcut.l3r3)
                        Text("L1 + R1").tag(EmulatorMenuShortcut.l1r1)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .onChange(of: menuShortcut) { _, newValue in
                        menuShortcutPreference.current = newValue
                        onChange()
                    }
                }
            }
        }
    }
}
