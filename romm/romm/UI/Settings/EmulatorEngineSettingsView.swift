import SwiftUI

struct EmulatorEngineSettingsView: View {
    @State private var selection: EmulatorEngine
    @State private var screenPosition: EmulatorScreenPosition
    @State private var heightFraction: Double
    private let preference: PEmulatorEnginePreference
    private let screenPositionPreference: PEmulatorScreenPositionPreference

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.preference = factory.enginePreference
        self.screenPositionPreference = factory.emulatorScreenPositionPreference
        _selection = State(wrappedValue: factory.enginePreference.current)
        _screenPosition = State(wrappedValue: factory.emulatorScreenPositionPreference.position)
        _heightFraction = State(wrappedValue: factory.emulatorScreenPositionPreference.heightFraction)
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
                footer: Text("Applies to the PlayStation (libretro) core. “Top” pins the game to the top and lets you pick how much of the height it uses — handy for physical gamepad cases so the lower part of the screen stays free for the controls.")
            ) {
                Picker("Screen Position", selection: $screenPosition) {
                    ForEach(EmulatorScreenPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                if screenPosition == .top {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Height")
                            Spacer()
                            Text("\(Int((heightFraction * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $heightFraction, in: 0.3...1.0, step: 0.05)
                    }
                }

                ScreenLayoutPreview(position: screenPosition, fraction: heightFraction)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .navigationTitle("Emulator")
        .onChange(of: selection) { _, new in preference.current = new }
        .onChange(of: screenPosition) { _, new in screenPositionPreference.position = new }
        .onChange(of: heightFraction) { _, new in screenPositionPreference.heightFraction = new }
    }
}

/// Small phone-shaped mockup that shows where the game screen will sit and how
/// much vertical space it takes, based on the current Screen Position settings.
private struct ScreenLayoutPreview: View {
    let position: EmulatorScreenPosition
    let fraction: Double

    private let phoneWidth: CGFloat = 104
    private let phoneHeight: CGFloat = 208
    private let inset: CGFloat = 6

    var body: some View {
        let innerWidth = phoneWidth - inset * 2
        let innerHeight = phoneHeight - inset * 2
        let frac = position == .top ? CGFloat(min(1.0, max(0.3, fraction))) : 1.0
        let blockHeight = innerHeight * frac

        VStack(spacing: 6) {
            ZStack(alignment: position == .top ? .top : .center) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: innerWidth, height: blockHeight)
                    .overlay(
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.9))
                    )
                    .padding(inset)
            }
            .frame(width: phoneWidth, height: phoneHeight)
            .animation(.easeInOut(duration: 0.15), value: frac)
            .animation(.easeInOut(duration: 0.15), value: position)

            Text("Preview")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
