import SwiftUI

struct EmulatorEngineSettingsView: View {
    @State private var selection: EmulatorEngine
    @State private var screenPosition: EmulatorScreenPosition
    private let preference: PEmulatorEnginePreference
    private let screenPositionPreference: PEmulatorScreenPositionPreference

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.preference = factory.enginePreference
        self.screenPositionPreference = factory.emulatorScreenPositionPreference
        _selection = State(wrappedValue: factory.enginePreference.current)
        _screenPosition = State(wrappedValue: factory.emulatorScreenPositionPreference.position)
    }

    var body: some View {
        Form {
            Section(header: Text("Engine")) {
                Picker("Engine", selection: $selection) {
                    Text("Web (EmulatorJS)").tag(EmulatorEngine.web)
                    Text("Native (DeltaCore, etc.)").tag(EmulatorEngine.native)
                }
                .pickerStyle(.inline)
            }
            Section(footer: Text("Native runs emulation on-device via embedded cores (DeltaCore for Game Boy / Color, GBA, NES, SNES, N64, Nintendo DS, Sega Genesis; libretro for PlayStation). Other platforms fall back to Web automatically.")) { EmptyView() }

            Section(
                header: Text("Screen Position"),
                footer: Text("Aligns the game screen to the top of the display instead of centering it. Useful for physical gamepad cases. Applies to the PlayStation (libretro) core.")
            ) {
                Picker("Screen Position", selection: $screenPosition) {
                    ForEach(EmulatorScreenPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Emulator")
        .onChange(of: selection) { _, new in preference.current = new }
        .onChange(of: screenPosition) { _, new in screenPositionPreference.position = new }
    }
}
