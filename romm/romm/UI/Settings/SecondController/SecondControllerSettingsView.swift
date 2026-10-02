import SwiftUI
import GameController

/// Everything about player two: another gamepad, or a phone on the network that
/// stands in for one.
struct SecondControllerSettingsView: View {

    @ObservedObject private var manager = SecondControllerManager.shared
    @SwiftUI.State private var acceptsRemotePad = SecondControllerManager.shared.acceptsRemotePad
    @SwiftUI.State private var connectedGamepads = GCController.controllers().count
    @SwiftUI.State private var showingRemoteController = false

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: connectedGamepads > 0 ? "gamecontroller.fill" : "gamecontroller")
                        .foregroundColor(connectedGamepads > 0 ? .accentColor : .secondary)
                    Text(gamepadStatus)
                }
            } header: {
                Text("Gamepads")
            } footer: {
                Text("Pair a second gamepad over Bluetooth in the iOS settings, or plug it in. The order they connect in is the order they play in.")
            }

            Section {
                Toggle(isOn: $acceptsRemotePad) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Phone as Second Controller")
                        Text("Let a phone on this network join as player two")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: acceptsRemotePad) { _, newValue in
                    manager.setAcceptsRemotePad(newValue)
                }

                if acceptsRemotePad {
                    HStack {
                        Image(systemName: manager.isPadConnected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3.slash")
                            .foregroundColor(manager.isPadConnected ? .accentColor : .secondary)
                        Text(manager.padName ?? "No phone connected")
                    }
                }
            } header: {
                Text("This phone")
            } footer: {
                Text("The other phone needs the RomM app and the same Wi-Fi, nothing else. It does not have to be signed in.")
            }

            Section {
                Button {
                    showingRemoteController = true
                } label: {
                    HStack {
                        Image(systemName: "dpad.fill")
                        Text("Play as Controller")
                    }
                }
            } header: {
                Text("Another phone")
            } footer: {
                Text("Use this phone as the pad for a game running somewhere else.")
            }
        }
        .navigationTitle("Second Controller")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRemoteController) {
            RemoteControllerView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
            connectedGamepads = GCController.controllers().count
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            connectedGamepads = GCController.controllers().count
        }
    }

    private var gamepadStatus: String {
        switch connectedGamepads {
        case 0: return "No gamepad connected"
        case 1: return "One gamepad connected"
        default: return "\(connectedGamepads) gamepads connected"
        }
    }
}
