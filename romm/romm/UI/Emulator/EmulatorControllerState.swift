import Foundation
import GameController
import SwiftUI

/// Single source of truth for "is a physical controller connected?", used to
/// drive Controller Mode (hide touch controls, enable drag-to-move, apply the
/// custom screen placement). In DEBUG builds a toggle can simulate a connected
/// controller so the behavior can be tested without pairing real hardware.
enum EmulatorControllerState {
    static var isConnected: Bool {
        #if DEBUG
        if simulateConnected { return true }
        #endif
        return !GCController.controllers().isEmpty
    }

    #if DEBUG
    private static let simulateKey = "debug.simulateController"

    /// When on, `isConnected` reports `true` regardless of real hardware.
    /// Setting it posts a notification so live sessions re-evaluate immediately.
    static var simulateConnected: Bool {
        get { UserDefaults.standard.bool(forKey: simulateKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: simulateKey)
            NotificationCenter.default.post(name: .emulatorSimulatedControllerChanged, object: nil)
        }
    }
    #endif
}

#if DEBUG
extension Notification.Name {
    static let emulatorSimulatedControllerChanged = Notification.Name("emulatorSimulatedControllerChanged")
}

/// Debug-only toggle (dark menu styling) that fakes a connected controller.
struct EmulatorControllerDebugToggle: View {
    @SwiftUI.State private var simulate = EmulatorControllerState.simulateConnected

    var body: some View {
        HStack {
            Label("Simulate controller", systemImage: "gamecontroller")
                .font(.subheadline)
                .foregroundColor(.yellow.opacity(0.9))
            Spacer()
            Toggle("", isOn: $simulate)
                .labelsHidden()
                .onChange(of: simulate) { _, newValue in
                    EmulatorControllerState.simulateConnected = newValue
                }
        }
    }
}
#endif
