import SwiftUI

struct EmulatorEngineSettingsView: View {
    @State private var selection: EmulatorEngine
    @State private var mode: ControllerScreenMode
    @State private var verticalOffset: Double
    @State private var heightFraction: Double
    private let preference: PEmulatorEnginePreference
    private let screenPositionPreference: PEmulatorScreenPositionPreference

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.preference = factory.enginePreference
        self.screenPositionPreference = factory.emulatorScreenPositionPreference
        _selection = State(wrappedValue: factory.enginePreference.current)
        _mode = State(wrappedValue: factory.emulatorScreenPositionPreference.mode)
        _verticalOffset = State(wrappedValue: factory.emulatorScreenPositionPreference.verticalOffset)
        _heightFraction = State(wrappedValue: factory.emulatorScreenPositionPreference.heightFraction)
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

            controllerModeSection
        }
        .navigationTitle("Emulator")
        .onChange(of: selection) { _, new in preference.current = new }
        .onChange(of: mode) { _, new in screenPositionPreference.mode = new }
        .onChange(of: verticalOffset) { _, new in screenPositionPreference.verticalOffset = new }
        .onChange(of: heightFraction) { _, new in screenPositionPreference.heightFraction = new }
    }

    // MARK: - Controller Mode

    // Only relevant for the on-device renderers (native + libretro). Hide it for
    // the Web (EmulatorJS) engine, where the setting does nothing.
    @ViewBuilder
    private var controllerModeSection: some View {
        if selection == .native {
            Section(
                header: Text("Controller Mode"),
                footer: Text("Repositions the game in portrait so a physical gamepad case (e.g. GameSir Pocket Taco) doesn't cover it. “Auto” only kicks in while a controller is connected; “On” always applies. Drag the game in the preview to place it, and use the bottom handle to set its height. Landscape already fills the screen, so this has no effect there.")
            ) {
                Picker("Mode", selection: $mode) {
                    ForEach(ControllerScreenMode.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.segmented)

                if mode != .off {
                    VStack(spacing: 14) {
                        ControllerScreenPreview(
                            verticalOffset: $verticalOffset,
                            heightFraction: $heightFraction
                        )
                        HStack {
                            Label("\(Int((verticalOffset * 100).rounded()))% from top", systemImage: "arrow.up.and.down")
                            Spacer()
                            Label("\(Int((heightFraction * 100).rounded()))% height", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

/// Interactive portrait phone mock: drag the game block to reposition it and
/// drag the bottom handle to resize its height. Writes back into the bound
/// `verticalOffset` (0 = top … 1 = bottom) and `heightFraction` (0.3…1.0).
private struct ControllerScreenPreview: View {
    @Binding var verticalOffset: Double
    @Binding var heightFraction: Double

    @State private var baseOffset: Double?
    @State private var baseHeight: Double?

    private let phoneWidth: CGFloat = 132
    private let phoneHeight: CGFloat = 264
    private let bezel: CGFloat = 9

    var body: some View {
        let innerW = phoneWidth - bezel * 2
        let innerH = phoneHeight - bezel * 2
        let frac = CGFloat(min(1.0, max(0.3, heightFraction)))
        let blockH = innerH * frac
        let freeSpace = innerH - blockH
        let blockTop = bezel + CGFloat(min(1.0, max(0.0, verticalOffset))) * freeSpace

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .frame(width: phoneWidth, height: phoneHeight)

            // Game surface — draggable to reposition.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: innerW, height: blockH)
                .overlay(
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.9))
                )
                .overlay(alignment: .bottom) { resizeHandle }
                .offset(x: bezel, y: blockTop)
                .gesture(repositionGesture(freeSpace: freeSpace))
        }
        .frame(width: phoneWidth, height: phoneHeight)
    }

    private var resizeHandle: some View {
        Capsule()
            .fill(.white.opacity(0.9))
            .frame(width: 40, height: 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle().inset(by: -12))
            .gesture(resizeGesture())
    }

    private func repositionGesture(freeSpace: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if baseOffset == nil { baseOffset = verticalOffset }
                guard freeSpace > 0 else { return }
                let delta = Double(value.translation.height / freeSpace)
                verticalOffset = min(1.0, max(0.0, (baseOffset ?? verticalOffset) + delta))
            }
            .onEnded { _ in baseOffset = nil }
    }

    private func resizeGesture() -> some Gesture {
        let innerH = phoneHeight - bezel * 2
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                if baseHeight == nil { baseHeight = heightFraction }
                let delta = Double(value.translation.height / innerH)
                heightFraction = min(1.0, max(0.3, (baseHeight ?? heightFraction) + delta))
            }
            .onEnded { _ in baseHeight = nil }
    }
}
