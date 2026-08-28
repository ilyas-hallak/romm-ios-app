import SwiftUI

/// Where a Play tap sends a game, across both the built-in engines and the
/// external apps.
///
/// These live in two separate preferences, but as a question to the user they
/// are one: a game runs either here or somewhere else, never both.
private enum PlayChoice: Hashable {
    case builtIn(EmulatorEngine)
    case external(ExternalEmulatorID)

    init(engine: EmulatorEngine, target: PlayTarget) {
        if let id = target.externalEmulatorID {
            self = .external(id)
        } else {
            self = .builtIn(Self.usableEngine(engine))
        }
    }

    /// `.auto`, and `.web` in builds without the web engine, have no row of their
    /// own, so they resolve to the one that does.
    private static func usableEngine(_ engine: EmulatorEngine) -> EmulatorEngine {
        guard AppFeatures.webEmulatorEnabled, engine == .web else { return .native }
        return .web
    }
}

struct EmulatorEngineSettingsView: View {
    @State private var playChoice: PlayChoice
    @State private var menuShortcut: EmulatorMenuShortcut
    @State private var swapFaceButtons: Bool
    @State private var installedEmulators: [ExternalEmulatorID] = []
    private let preference: PEmulatorEnginePreference
    private let menuShortcutPreference: PEmulatorMenuShortcutPreference
    private let faceButtonPreference: PGamepadFaceButtonPreference
    private let playTargetPreference: PPlayTargetPreference
    private let externalAppLauncher: PExternalAppLauncher

    #if DEBUG
    @State private var simulateController = EmulatorControllerState.simulateConnected
    #endif

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.preference = factory.enginePreference
        self.menuShortcutPreference = factory.emulatorMenuShortcutPreference
        self.faceButtonPreference = factory.gamepadFaceButtonPreference
        self.playTargetPreference = factory.playTargetPreference
        self.externalAppLauncher = factory.externalAppLauncher
        _menuShortcut = State(wrappedValue: factory.emulatorMenuShortcutPreference.current)
        _swapFaceButtons = State(wrappedValue: factory.gamepadFaceButtonPreference.isSwapped)
        _playChoice = State(wrappedValue: PlayChoice(
            engine: factory.enginePreference.current,
            target: factory.playTargetPreference.current
        ))
    }

    var body: some View {
        Form {
            playWithSection

            Section(footer: Text("When a physical controller is connected, the on-screen buttons hide and you can drag the game to reposition it — handy for gamepad cases that cover part of the screen. Set its size from the in-game menu.")) { EmptyView() }

            Section(
                header: Text("Controller"),
                footer: Text("Optional button combination that opens the in-game menu from a physical controller. The on-screen menu button stays available either way.")
            ) {
                Picker("Menu shortcut", selection: $menuShortcut) {
                    Text("Off").tag(EmulatorMenuShortcut.none)
                    Text("L3 + R3").tag(EmulatorMenuShortcut.l3r3)
                    Text("L1 + R1").tag(EmulatorMenuShortcut.l1r1)
                }
            }

            Section(footer: Text("Face buttons are read by position, never by the label printed on them, so a Nintendo-style pad ends up with A and B the wrong way round. Turn this on if the buttons in a game don't match your controller.")) {
                Toggle("Swap A/B and X/Y", isOn: $swapFaceButtons)
            }

            #if DEBUG
            Section(
                header: Text("Debug"),
                footer: Text("Pretends a physical controller is connected, so Controller Mode (hidden touch controls, drag-to-move, height slider) can be tested without pairing real hardware.")
            ) {
                Toggle("Simulate connected controller", isOn: $simulateController)
                    .onChange(of: simulateController) { _, new in
                        EmulatorControllerState.simulateConnected = new
                    }
            }
            #endif
        }
        .navigationTitle("Emulator")
        .onAppear { refreshInstalledEmulators() }
        .onChange(of: menuShortcut) { _, new in menuShortcutPreference.current = new }
        .onChange(of: swapFaceButtons) { _, new in faceButtonPreference.isSwapped = new }
        .onChange(of: playChoice) { _, new in apply(new) }
    }

    /// One list for where a game runs, built-in engines first, then the apps a
    /// ROM can be handed to.
    @ViewBuilder
    private var playWithSection: some View {
        Section(header: Text("Play with"), footer: Text(footerText)) {
            if choices.count > 1 {
                Picker("Play with", selection: $playChoice) {
                    ForEach(choices, id: \.self) { choice in
                        Text(label(for: choice)).tag(choice)
                    }
                }
                .pickerStyle(.inline)
            } else {
                // Nothing to choose between, so a picker would only look broken.
                HStack {
                    Text("Play with")
                    Spacer()
                    Text(label(for: playChoice)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var choices: [PlayChoice] {
        var choices: [PlayChoice] = AppFeatures.webEmulatorEnabled
            ? [.builtIn(.web), .builtIn(.native)]
            : [.builtIn(.native)]
        choices += pickableEmulators.map { .external($0) }
        return choices
    }

    private func label(for choice: PlayChoice) -> String {
        switch choice {
        case .builtIn(let engine):
            guard AppFeatures.webEmulatorEnabled else { return "Built-in emulator" }
            return engine == .web ? "Web (EmulatorJS)" : "Native (DeltaCore, etc.)"
        case .external(let id):
            return "External: \(id.emulator.displayName)"
        }
    }

    private var footerText: String {
        guard !pickableEmulators.isEmpty else {
            return "Install \(supportedEmulatorNames) to play ROMs there instead of on this device."
        }
        return "An external app is handed the ROM once through the system menu, then opens it directly. Save states are not shared between apps."
    }

    private func apply(_ choice: PlayChoice) {
        switch choice {
        case .builtIn(let engine):
            preference.current = engine
            playTargetPreference.current = .builtIn
        case .external(let id):
            playTargetPreference.current = .external(id)
        }
    }

    /// Installed apps, plus whatever is currently selected so an uninstalled
    /// choice does not silently disappear from the picker.
    private var pickableEmulators: [ExternalEmulatorID] {
        guard case .external(let selected) = playChoice, !installedEmulators.contains(selected) else {
            return installedEmulators
        }
        return installedEmulators + [selected]
    }

    /// Every app Play can hand a ROM to, for the "nothing installed yet" hint.
    private var supportedEmulatorNames: String {
        ListFormatter.localizedString(
            byJoining: ExternalEmulatorID.allCases.map { $0.emulator.displayName }
        )
    }

    private func refreshInstalledEmulators() {
        installedEmulators = ExternalEmulatorID.allCases.filter { externalAppLauncher.isInstalled($0.emulator) }
    }
}
