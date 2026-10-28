import SwiftUI

/// The alerts a Play tap can end in: the intro before the first handoff, the
/// pasteboard hint, the question whether a ROM copied earlier is already in the
/// target, and the error alert.
struct ExternalPlayAlertsModifier: ViewModifier {
    let coordinator: ExternalPlayCoordinator

    func body(content: Content) -> some View {
        content
            .alert(
                "First Time in \(coordinator.handoffIntro?.appName ?? "the Emulator")",
                isPresented: Binding(
                    get: { coordinator.handoffIntro != nil },
                    set: { if !$0 { coordinator.cancelHandoffIntro() } }
                ),
                presenting: coordinator.handoffIntro
            ) { _ in
                Button("Continue") { coordinator.continueAfterHandoffIntro() }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { coordinator.cancelHandoffIntro() }
            } message: { intro in
                Text("Pick \(intro.appName) in the menu that opens next. "
                    + "This copies the game over. Tap Play again to start it, "
                    + "from then on it opens straight away.")
            }
            .alert(
                "ROM Copied",
                isPresented: Binding(
                    get: { coordinator.pasteboardHandoff != nil },
                    set: { if !$0 { coordinator.dismissPasteboardHandoff() } }
                ),
                presenting: coordinator.pasteboardHandoff
            ) { handoff in
                Button("Open \(handoff.appName)") { coordinator.openPasteboardTarget() }
                Button("Done", role: .cancel) { coordinator.dismissPasteboardHandoff() }
            } message: { handoff in
                Text("\(handoff.romName) is on the clipboard. "
                    + "Open \(handoff.appName) and tap Paste to import it.")
            }
            .alert(
                "Already in \(coordinator.relaunchConfirmation?.appName ?? "the emulator")?",
                isPresented: Binding(
                    get: { coordinator.relaunchConfirmation != nil },
                    set: { if !$0 { coordinator.cancelRelaunchConfirmation() } }
                ),
                presenting: coordinator.relaunchConfirmation
            ) { confirmation in
                Button("Launch") { coordinator.confirmAlreadyInTarget() }
                    .keyboardShortcut(.defaultAction)
                Button("Copy Again") { coordinator.copyToTargetAgain() }
                Button("Cancel", role: .cancel) { coordinator.cancelRelaunchConfirmation() }
            } message: { confirmation in
                Text("If \(confirmation.appName) already imported this ROM from the clipboard, "
                    + "Launch opens it directly. Otherwise copy it over again.")
            }
            .alert(
                "Cannot Play",
                isPresented: Binding(
                    get: { coordinator.errorMessage != nil },
                    set: { if !$0 { coordinator.errorMessage = nil } }
                ),
                presenting: coordinator.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { coordinator.errorMessage = nil }
            } message: { message in
                Text(message)
            }
    }
}

extension View {
    func externalPlayAlerts(_ coordinator: ExternalPlayCoordinator) -> some View {
        modifier(ExternalPlayAlertsModifier(coordinator: coordinator))
    }
}
