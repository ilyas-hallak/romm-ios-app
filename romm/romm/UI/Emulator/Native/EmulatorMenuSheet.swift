#if !APP_STORE
import SwiftUI

struct EmulatorMenuSheet: View {
    let session: NativeEmulatorSession?
    let faceButtonPreference: PGamepadFaceButtonPreference
    let menuShortcutPreference: PEmulatorMenuShortcutPreference
    let onResume: () -> Void
    let onQuit: () -> Void

    @SwiftUI.State private var selectedSlot: Int
    @SwiftUI.State private var statusMessage: String?
    @SwiftUI.State private var refreshTick: Int = 0
    @SwiftUI.State private var isFastForwarding: Bool
    @SwiftUI.State private var showQuitConfirmation = false
    @SwiftUI.State private var focus: EmulatorMenuFocus<MenuItem>
    @ObservedObject private var externalDisplay = ExternalDisplayManager.shared

    // Slots are 0-based to match the save-state storage / cloud-sync layer
    // (files are `slot0.state`…`slot20.state`). Slot 0 is a real, usable slot.
    private let slots = Array(0...20)

    /// What a controller can reach. The settings rows are left out, they are
    /// not something to change mid-game with a pad.
    private enum MenuItem: Hashable {
        case quit, done
        case slot
        case fastForward
        case load, save, undoSave, undoLoad
    }

    init(
        session: NativeEmulatorSession?,
        faceButtonPreference: PGamepadFaceButtonPreference,
        menuShortcutPreference: PEmulatorMenuShortcutPreference,
        onResume: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.session = session
        self.faceButtonPreference = faceButtonPreference
        self.menuShortcutPreference = menuShortcutPreference
        self.onResume = onResume
        self.onQuit = onQuit
        // Pre-select the most recently touched slot so existing saves are
        // immediately visible and loadable after the 1→0 slot renumbering (PR #57).
        let mostRecent = slots.compactMap { slot -> (slot: Int, date: Date)? in
            guard let date = session?.stateModifiedAt(slot: slot) else { return nil }
            return (slot, date)
        }.max(by: { $0.date < $1.date })?.slot ?? 0
        self._selectedSlot = SwiftUI.State(initialValue: mostRecent)
        let initial: MenuItem = session?.hasState(slot: mostRecent) == true ? .load : .save
        self._focus = SwiftUI.State(initialValue: EmulatorMenuFocus(
            rows: [[.quit, .done], [.slot], [.fastForward], [.load, .save, .undoSave, .undoLoad]],
            initial: initial,
            adjustableItems: [.slot]
        ))
        self._isFastForwarding = SwiftUI.State(initialValue: session?.isFastForwarding ?? false)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                // One scroll view for everything, like the libretro menu. The
                // slot list used to scroll on its own inside a fixed stack, which
                // squeezed it as soon as an optional section above appeared.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            detailHeader
                            fastForwardButton
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                            actionButtons
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            // Still gated on a real display, unlike the libretro menu
                            // which always shows the section. Settings carries the
                            // discoverability.
                            if externalDisplay.isConnected {
                                Divider().background(Color.white.opacity(0.1))
                                ExternalDisplayControls(onRequestDismiss: onResume)
                                    .padding(16)
                            }
                            if EmulatorControllerState.isConnected {
                                Divider().background(Color.white.opacity(0.1))
                                EmulatorControllerControls(
                                    faceButtonPreference: faceButtonPreference,
                                    menuShortcutPreference: menuShortcutPreference,
                                    style: .inlineRows
                                ) {
                                    session?.reloadFaceButtonMapping()
                                    session?.reloadMenuShortcut()
                                }
                                .padding(16)
                            }
                            if let preference = session?.screenPositionPreference,
                               EmulatorControllerState.isConnected {
                                Divider().background(Color.white.opacity(0.1))
                                EmulatorScreenControls(preference: preference) {
                                    session?.refreshScreenPlacement()
                                }
                                .padding(16)
                            }
                            #if DEBUG
                            Divider().background(Color.white.opacity(0.1))
                            EmulatorControllerDebugToggle()
                                .padding(16)
                            #endif
                            Divider().background(Color.white.opacity(0.1))
                            slotList
                        }
                    }
                    .onChange(of: focus.focused) { _, item in
                        withAnimation { proxy.scrollTo(item) }
                    }
                }
            }
            .navigationTitle("Save States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        showQuitConfirmation = true
                    } label: {
                        EmulatorMenuToolbarLabel(title: "Quit", isFocused: focus.isFocused(.quit))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onResume) {
                        EmulatorMenuToolbarLabel(title: "Done", isFocused: focus.isFocused(.done))
                    }
                    .bold()
                }
            }
            .emulatorMenuQuitConfirmation(
                isPresented: $showQuitConfirmation,
                showsControllerHint: focus.isVisible,
                onQuit: onQuit
            )
        }
        .onAppear {
            session?.onMenuCommand = { handle($0) }
        }
        .onDisappear {
            session?.onMenuCommand = nil
        }
    }

    // MARK: - Controller

    private func handle(_ command: EmulatorMenuCommand) {
        if showQuitConfirmation {
            command.answerQuitConfirmation(quit: onQuit, cancel: { showQuitConfirmation = false })
            return
        }
        switch focus.handle(command) {
        case .activate(let item): activate(item)
        case .adjust(_, let step): selectedSlot = min(max(selectedSlot + step, slots.first!), slots.last!)
        case .dismiss: onResume()
        case .none: break
        }
    }

    private func activate(_ item: MenuItem) {
        switch item {
        case .quit: showQuitConfirmation = true
        case .done: onResume()
        case .fastForward: toggleFastForward()
        case .load where canLoad: load()
        case .save: save()
        case .undoSave where canUndoSave: undoSave()
        case .undoLoad where canUndoLoad: undoLoad()
        default: break
        }
    }

    private var detailHeader: some View {
        VStack(spacing: 10) {
            previewArea
            HStack(spacing: 8) {
                Text("Slot \(selectedSlot)")
                    .font(.headline)
                    .foregroundColor(.white)
                if focus.isFocused(.slot) {
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                if let date = session?.stateModifiedAt(slot: selectedSlot) {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    Text("Empty")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            // The ring gets room around the row without moving the text out of
            // line with the preview above it.
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .emulatorMenuFocusRing(focus.isFocused(.slot), cornerRadius: 8)
            .padding(.horizontal, -8)
            .padding(.vertical, -6)
            .id(MenuItem.slot)
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .id(refreshTick)
    }

    @ViewBuilder
    private var previewArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
            if let image = session?.thumbnail(slot: selectedSlot) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                    Text("No save state")
                        .font(.footnote)
                }
                .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(height: 180)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// Part of the sheet's own scroll view, not a scroll view of its own. The
    /// list is a fixed 21 rows, so a plain stack is enough and nesting two
    /// vertical scroll views is avoided.
    private var slotList: some View {
        VStack(spacing: 0) {
            ForEach(slots, id: \.self) { slot in
                slotRow(slot)
                if slot != slots.last {
                    Divider().background(Color.white.opacity(0.06))
                        .padding(.leading, 16)
                }
            }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func slotRow(_ slot: Int) -> some View {
        let isSelected = slot == selectedSlot
        let occupied = session?.hasState(slot: slot) == true
        Button {
            selectedSlot = slot
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 26, height: 26)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                Text("Slot \(slot)")
                    .font(.body)
                    .foregroundColor(.white)
                Spacer()
                if occupied {
                    Circle().fill(.green).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            stackedButton(
                title: "Load",
                icon: "tray.and.arrow.up",
                tint: .accentColor,
                filled: true,
                disabled: !canLoad,
                item: .load,
                action: load
            )
            stackedButton(
                title: "Save",
                icon: "tray.and.arrow.down",
                tint: .accentColor,
                filled: false,
                disabled: false,
                item: .save,
                action: save
            )
            stackedButton(
                title: "Undo Save",
                icon: "arrow.uturn.backward",
                tint: .orange,
                filled: false,
                disabled: !canUndoSave,
                item: .undoSave,
                action: undoSave
            )
            stackedButton(
                title: "Undo Load",
                icon: "arrow.uturn.backward.circle",
                tint: .orange,
                filled: false,
                disabled: !canUndoLoad,
                item: .undoLoad,
                action: undoLoad
            )
        }
        .id(MenuItem.load)
    }

    private var canLoad: Bool { session?.hasState(slot: selectedSlot) == true }
    private var canUndoSave: Bool { session?.hasUndoSave(slot: selectedSlot) == true }
    private var canUndoLoad: Bool { session?.hasUndoLoad() == true }

    private func load() {
        let slot = selectedSlot
        perform(
            success: "Slot \(slot) loaded",
            action: { try await session?.loadState(slot: slot) },
            onSuccess: { onResume() }
        )
    }

    private func save() {
        let slot = selectedSlot
        perform(
            success: "Slot \(slot) saved",
            action: { try await session?.saveState(slot: slot) },
            onSuccess: { refreshTick += 1 }
        )
    }

    private func undoSave() {
        let slot = selectedSlot
        perform(
            success: "Save for slot \(slot) undone",
            action: { try session?.undoSave(slot: slot) },
            onSuccess: { refreshTick += 1 }
        )
    }

    private func undoLoad() {
        perform(
            success: "Load undone",
            action: { try session?.undoLoad() },
            onSuccess: { onResume() }
        )
    }

    private func toggleFastForward() {
        isFastForwarding = session?.toggleFastForward() ?? false
    }

    private var fastForwardButton: some View {
        Button(action: toggleFastForward) {
            HStack(spacing: 12) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fast Forward")
                        .font(.body.weight(.semibold))
                    Text("2x speed")
                        .font(.caption)
                }
                Spacer()
                Text(isFastForwarding ? "On" : "Off")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: isFastForwarding ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isFastForwarding ? Color.accentColor : .white.opacity(0.45))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFastForwarding ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isFastForwarding ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
            )
            .emulatorMenuFocusRing(focus.isFocused(.fastForward))
        }
        .buttonStyle(.plain)
        .id(MenuItem.fastForward)
        .disabled(session == nil)
        .opacity(session == nil ? 0.35 : 1)
    }

    @ViewBuilder
    private func stackedButton(
        title: String,
        icon: String,
        tint: Color,
        filled: Bool,
        disabled: Bool,
        item: MenuItem,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(filled ? .black : tint)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(filled ? tint : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(filled ? Color.clear : tint.opacity(0.4), lineWidth: 1)
            )
            .opacity(disabled ? 0.35 : 1)
            .emulatorMenuFocusRing(focus.isFocused(item))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// Success message and follow-up only fire on success. They used to run
    /// unconditionally, overwriting the error and hiding failed saves.
    private func perform(
        success: String,
        action: @escaping () async throws -> Void,
        onSuccess: @escaping () -> Void = {}
    ) {
        Task {
            do {
                try await action()
                statusMessage = success
                onSuccess()
            } catch {
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
}

struct EmulatorLoadingOverlay: View {
    let romName: String
    @SwiftUI.State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 4)
                        .frame(width: 88, height: 88)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(pulse ? 360 : 0))
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .scaleEffect(pulse ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                }
                VStack(spacing: 6) {
                    Text("Loading ROM…")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(romName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
        }
        .onAppear { pulse = true }
    }
}

struct EmulatorErrorOverlay: View {
    let message: String
    let onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40)).foregroundColor(.red)
            Text(message).foregroundColor(.white).multilineTextAlignment(.center)
            Button("Close", action: onDismiss).foregroundColor(.white)
        }
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.9)))
        .padding()
    }
}
#endif
