import SwiftUI

/// Settings for playing on a TV. The in-game menu carries the same two switches
/// for changing them mid-session, this is where they can be set up beforehand.
struct ExternalDisplaySettingsView: View {

    @SwiftUI.State private var playOnTV = ExternalDisplayPreferences.isEnabled
    @SwiftUI.State private var autoDim = ExternalDisplayPreferences.autoDimPhone
    @ObservedObject private var display = ExternalDisplayManager.shared

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: display.isConnected ? "tv.fill" : "tv.slash")
                        .foregroundColor(display.isConnected ? .accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.isConnected ? "Display connected" : "No display connected")
                        if let resolution = display.displayResolution {
                            Text(resolution)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Start Screen Mirroring from Control Center, or plug in a USB-C to HDMI adapter. No app is allowed to start mirroring itself, so this step is always yours. A cable has almost no lag, AirPlay adds roughly 100 ms.")
            }

            Section {
                Toggle(isOn: $playOnTV) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play on TV")
                        Text("Send just the game instead of mirroring the phone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: playOnTV) { _, newValue in
                    ExternalDisplayManager.shared.setEnabled(newValue)
                }

                Toggle(isOn: $autoDim) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dim phone screen")
                        Text("Goes dark by itself while the game is on the TV and a controller is connected. A tap brings it back.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: autoDim) { _, newValue in
                    ExternalDisplayPreferences.autoDimPhone = newValue
                }
            } header: {
                Text("Options")
            } footer: {
                Text("With Play on TV the game is drawn at the TV's own resolution, so no portrait phone screen with black bars. Turn it off to go back to plain mirroring.")
            }
        }
        .navigationTitle("Play on TV")
        .navigationBarTitleDisplayMode(.inline)
    }
}
