import SwiftUI

struct EmulatorEngineSettingsView: View {
    @State private var selection: EmulatorEngine
    @State private var menuShortcut: EmulatorMenuShortcut
    @State private var playTarget: PlayTarget
    @State private var installedEmulators: [ExternalEmulator] = []
    private let preference: PEmulatorEnginePreference
    private let menuShortcutPreference: PEmulatorMenuShortcutPreference
    private let playTargetPreference: PPlayTargetPreference
    private let externalAppLauncher: PExternalAppLauncher

    #if DEBUG
    @State private var simulateController = EmulatorControllerState.simulateConnected
    #endif

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.preference = factory.enginePreference
        self.menuShortcutPreference = factory.emulatorMenuShortcutPreference
        self.playTargetPreference = factory.playTargetPreference
        self.externalAppLauncher = factory.externalAppLauncher
        _selection = State(wrappedValue: factory.enginePreference.current)
        _menuShortcut = State(wrappedValue: factory.emulatorMenuShortcutPreference.current)
        _playTarget = State(wrappedValue: factory.playTargetPreference.current)
    }

    var body: some View {
        Form {
            if AppFeatures.webEmulatorEnabled {
                Section(header: Text("Engine")) {
                    Picker("Engine", selection: $selection) {
                        Text("Web (EmulatorJS)").tag(EmulatorEngine.web)
                        Text("Native (DeltaCore, etc.)").tag(EmulatorEngine.native)
                    }
                    .pickerStyle(.inline)
                }
                Section(footer: Text("Native runs emulation on-device via embedded cores (DeltaCore for Game Boy / Color, GBA, NES, SNES, N64, Nintendo DS, Sega Genesis; libretro for PlayStation). Other platforms fall back to Web automatically.")) { EmptyView() }
            } else {
                Section(footer: Text("Emulation runs on-device via embedded native cores: DeltaCore for Game Boy / Color, GBA, NES, SNES, N64, Nintendo DS, Sega Genesis; libretro for PlayStation. Other platforms are not supported.")) {
                    HStack {
                        Text("Engine")
                        Spacer()
                        Text("Native").foregroundStyle(.secondary)
                    }
                }
            }

            playTargetSection

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
        .onChange(of: selection) { _, new in preference.current = new }
        .onChange(of: menuShortcut) { _, new in menuShortcutPreference.current = new }
        .onChange(of: playTarget) { _, new in playTargetPreference.current = new }
    }

    /// Lets Play hand the ROM to another emulator app instead of running it here.
    @ViewBuilder
    private var playTargetSection: some View {
        if installedEmulators.isEmpty && playTarget == .builtIn {
            Section(
                header: Text("Play with"),
                footer: Text("Install RetroArch to play ROMs there instead of in the built-in emulator.")
            ) {
                HStack {
                    Text("Play with")
                    Spacer()
                    Text("Built-in emulator").foregroundStyle(.secondary)
                }
            }
        } else {
            Section(
                header: Text("Play with"),
                footer: Text("The first time a ROM goes to another app you pick it from the system menu, which also imports the file. Every Play after that opens it there directly. Save states are not shared between the apps.")
            ) {
                Picker("Play with", selection: $playTarget) {
                    Text("Built-in emulator").tag(PlayTarget.builtIn)
                    ForEach(pickableEmulators, id: \.self) { emulator in
                        Text(emulator.displayName).tag(PlayTarget.external(emulator))
                    }
                }
            }
        }
    }

    /// Installed apps, plus whatever is currently selected so an uninstalled
    /// choice does not silently disappear from the picker.
    private var pickableEmulators: [ExternalEmulator] {
        guard let selected = playTarget.externalEmulator, !installedEmulators.contains(selected) else {
            return installedEmulators
        }
        return installedEmulators + [selected]
    }

    private func refreshInstalledEmulators() {
        installedEmulators = ExternalEmulator.allCases.filter(externalAppLauncher.isInstalled)
    }
}
