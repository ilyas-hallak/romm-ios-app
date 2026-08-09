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

            // Screen Position only affects the native (libretro) renderer — hide
            // it entirely for the Web (EmulatorJS) engine, where it does nothing.
            if selection == .native {
                Section(
                    header: Text("Screen Position"),
                    footer: Text("Applies to the PlayStation (libretro) core in portrait. “Top” pins the game to the top and lets you pick how much of the height it uses — handy for physical gamepad cases so the lower part of the screen stays free for the controls. In landscape the game already fills the height, so this setting has no effect there.")
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
        }
        .navigationTitle("Emulator")
        .onChange(of: selection) { _, new in preference.current = new }
        .onChange(of: screenPosition) { _, new in screenPositionPreference.position = new }
        .onChange(of: heightFraction) { _, new in screenPositionPreference.heightFraction = new }
    }
}

/// Side-by-side phone mockups that show where the game screen will sit.
/// The portrait mock reflects the current Screen Position settings; the
/// landscape mock illustrates that the game always fills the height there,
/// so the setting has no effect in landscape.
private struct ScreenLayoutPreview: View {
    let position: EmulatorScreenPosition
    let fraction: Double

    private let inset: CGFloat = 5

    var body: some View {
        let frac = position == .top ? CGFloat(min(1.0, max(0.3, fraction))) : 1.0

        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 6) {
                phone(
                    width: 84, height: 168,
                    alignment: position == .top ? .top : .center,
                    blockWidth: 84 - inset * 2,
                    blockHeight: (168 - inset * 2) * frac
                )
                Text("Portrait")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                // Landscape: a 4:3 picture already fills the full height and is
                // pillar-boxed on the sides — the setting can't move it.
                phone(
                    width: 168, height: 84,
                    alignment: .center,
                    blockWidth: (84 - inset * 2) * (4.0 / 3.0),
                    blockHeight: 84 - inset * 2
                )
                Text("Landscape · no effect")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.15), value: frac)
        .animation(.easeInOut(duration: 0.15), value: position)
    }

    private func phone(
        width: CGFloat,
        height: CGFloat,
        alignment: Alignment,
        blockWidth: CGFloat,
        blockHeight: CGFloat
    ) -> some View {
        ZStack(alignment: alignment) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: blockWidth, height: blockHeight)
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.9))
                )
                .padding(inset)
        }
        .frame(width: width, height: height)
    }
}
