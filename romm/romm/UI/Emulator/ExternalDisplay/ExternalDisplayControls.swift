import SwiftUI
import GameController

/// In-game section for playing on a TV. Shared by both emulator menus.
///
/// Deliberately not a device picker: iOS has no public API to start screen
/// mirroring or to choose its destination, that is reserved for Control Center.
/// So this shows what is attached, hands the display between our own picture and
/// plain mirroring, and tells the player what to do when nothing is connected.
struct ExternalDisplayControls: View {

    /// Called before dimming the phone, so the caller can close its menu first.
    var onRequestDismiss: () -> Void = {}

    @ObservedObject private var display = ExternalDisplayManager.shared

    @SwiftUI.State private var playOnTV: Bool = ExternalDisplayManager.shared.isPlayOnTVEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Play on TV", systemImage: "tv")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if display.isConnected {
                    Toggle("", isOn: $playOnTV)
                        .labelsHidden()
                        .onChange(of: playOnTV) { _, newValue in
                            display.setPlayOnTVEnabled(newValue)
                        }
                } else {
                    Text("Not connected")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Text(statusText)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)

            // Only worth offering once the TV really shows the game and the
            // player has a controller, otherwise it just hides the game.
            if display.isActive, EmulatorControllerState.isConnected {
                Button {
                    onRequestDismiss()
                    PhoneScreenBlanker.shared.blank()
                } label: {
                    Label("Turn off phone screen", systemImage: "iphone.slash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var statusText: String {
        guard display.isConnected else {
            return "Open Control Center and tap Screen Mirroring, or plug in a USB-C to HDMI adapter. A cable has almost no lag, AirPlay always has some."
        }
        let resolution = display.displayResolution.map { " at \($0)" } ?? ""
        return display.isActive
            ? "Showing the game on the display\(resolution)."
            : "The display is mirroring this screen, bars and all. Turn this on to send just the game."
    }
}
