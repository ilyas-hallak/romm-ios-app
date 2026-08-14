import SwiftUI

struct EmulatorEngineSettingsView: View {
    @State private var selection: EmulatorEngine
    private let preference: PEmulatorEnginePreference

    #if DEBUG
    @State private var simulateController = EmulatorControllerState.simulateConnected
    #endif

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.preference = factory.enginePreference
        _selection = State(wrappedValue: factory.enginePreference.current)
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

            Section(footer: Text("When a physical controller is connected, the on-screen buttons hide and you can drag the game to reposition it — handy for gamepad cases that cover part of the screen. Set its size from the in-game menu.")) { EmptyView() }

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
        .onChange(of: selection) { _, new in preference.current = new }
    }
}
