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
    /// The two menus label their blocks differently, so the block follows
    /// whichever one is showing it.
    enum Style {
        /// Caption heading above the rows, next to the libretro menu's own
        /// "Haptics" and friends.
        case section
        /// No heading, the rows carry a symbol instead, like the native menu's
        /// "Play on TV" and "Screen size" neighbors.
        case inlineRows
    }

    let faceButtonPreference: PGamepadFaceButtonPreference
    /// `nil` hides the shortcut picker, for callers that have no combo detection
    /// behind them. Both engines evaluate it.
    let menuShortcutPreference: PEmulatorMenuShortcutPreference?
    let style: Style
    /// Called after a change so the running session can re-apply it live.
    var onChange: () -> Void = {}

    @SwiftUI.State private var swapFaceButtons: Bool
    @SwiftUI.State private var menuShortcut: EmulatorMenuShortcut

    init(
        faceButtonPreference: PGamepadFaceButtonPreference,
        menuShortcutPreference: PEmulatorMenuShortcutPreference? = nil,
        style: Style = .section,
        onChange: @escaping () -> Void = {}
    ) {
        self.faceButtonPreference = faceButtonPreference
        self.menuShortcutPreference = menuShortcutPreference
        self.style = style
        self.onChange = onChange
        self._swapFaceButtons = SwiftUI.State(initialValue: faceButtonPreference.isSwapped)
        self._menuShortcut = SwiftUI.State(initialValue: menuShortcutPreference?.current ?? .none)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if style == .section {
                Text("Controller")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            HStack {
                rowLabel("Swap A/B and X/Y", symbol: "gamecontroller")
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
                    rowLabel("Menu shortcut", symbol: "line.3.horizontal")
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

    /// The heading is what tells the libretro menu these rows belong together, so
    /// without it every row has to say so itself, through its symbol.
    @ViewBuilder
    private func rowLabel(_ title: String, symbol: String) -> some View {
        Group {
            switch style {
            case .section:
                Text(title)
            case .inlineRows:
                // Fixed symbol column, otherwise the two rows sit on different
                // text edges: the gamepad glyph is wider than the menu glyph.
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: symbol).frame(width: 22)
                }
            }
        }
        .font(.subheadline)
        .foregroundColor(.white.opacity(0.7))
        .fixedSize(horizontal: true, vertical: false)
    }
}
