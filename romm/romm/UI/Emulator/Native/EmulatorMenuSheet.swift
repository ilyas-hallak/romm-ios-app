import SwiftUI

struct EmulatorMenuSheet: View {
    let session: NativeEmulatorSession?
    let onResume: () -> Void
    let onQuit: () -> Void

    @SwiftUI.State private var selectedSlot: Int = 0
    @SwiftUI.State private var statusMessage: String?
    @SwiftUI.State private var refreshTick: Int = 0
    @SwiftUI.State private var showQuitConfirmation = false

    // Slots are 0-based to match the save-state storage / cloud-sync layer
    // (files are `slot0.state`…`slot20.state`). Slot 0 is a real, usable slot.
    private let slots = Array(0...20)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    detailHeader
                    actionButtons
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
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
            .navigationTitle("Save States")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.9), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Quit", role: .destructive) {
                        showQuitConfirmation = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onResume).bold()
                }
            }
            .alert(
                "Quit Game?",
                isPresented: $showQuitConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive, action: onQuit)
            } message: {
                Text("Unsaved progress will be lost.")
            }
        }
    }

    private var detailHeader: some View {
        VStack(spacing: 10) {
            previewArea
            HStack(spacing: 8) {
                Text("Slot \(selectedSlot)")
                    .font(.headline)
                    .foregroundColor(.white)
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

    private var slotList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(slots, id: \.self) { slot in
                    slotRow(slot)
                    if slot != slots.last {
                        Divider().background(Color.white.opacity(0.06))
                            .padding(.leading, 16)
                    }
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
                disabled: session?.hasState(slot: selectedSlot) != true
            ) {
                perform { try session?.loadState(slot: selectedSlot) }
                statusMessage = "Slot \(selectedSlot) loaded"
                onResume()
            }
            stackedButton(
                title: "Save",
                icon: "tray.and.arrow.down",
                tint: .accentColor,
                filled: false,
                disabled: false
            ) {
                perform { try session?.saveState(slot: selectedSlot) }
                statusMessage = "Slot \(selectedSlot) saved"
                refreshTick += 1
            }
            stackedButton(
                title: "Undo Save",
                icon: "arrow.uturn.backward",
                tint: .orange,
                filled: false,
                disabled: session?.hasUndoSave(slot: selectedSlot) != true
            ) {
                perform { try session?.undoSave(slot: selectedSlot) }
                statusMessage = "Save for slot \(selectedSlot) undone"
                refreshTick += 1
            }
            stackedButton(
                title: "Undo Load",
                icon: "arrow.uturn.backward.circle",
                tint: .orange,
                filled: false,
                disabled: session?.hasUndoLoad() != true
            ) {
                perform { try session?.undoLoad() }
                statusMessage = "Load undone"
                onResume()
            }
        }
    }

    @ViewBuilder
    private func stackedButton(
        title: String,
        icon: String,
        tint: Color,
        filled: Bool,
        disabled: Bool,
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
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
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
