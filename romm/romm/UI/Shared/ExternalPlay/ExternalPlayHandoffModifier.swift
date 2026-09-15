import SwiftUI

/// Attaches everything a Play tap needs to reach an external emulator app: the
/// system "Open in" menu, the share sheet for ROMs that menu cannot carry, the
/// hint for targets that take the ROM off the pasteboard, and the error alert.
///
/// The ROM detail screen wires its own instead, because there the menu has to
/// be anchored to the Play button for the iPad popover.
struct ExternalPlayHandoffModifier: ViewModifier {
    let coordinator: ExternalPlayCoordinator

    func body(content: Content) -> some View {
        content
            .background(
                OpenInMenuPresenter(
                    item: coordinator.openInItem,
                    onSent: { coordinator.handoffDidComplete(receivingBundleIdentifier: $0) },
                    onDismiss: { coordinator.openInItem = nil },
                    onNoTargets: { coordinator.handoffFoundNoTargets() }
                )
            )
            .sheet(
                item: Binding(
                    get: { coordinator.shareItem },
                    set: { coordinator.shareItem = $0 }
                ),
                onDismiss: { coordinator.cleanupShareTemp() },
                content: { item in
                    ShareSheet(activityItems: item.urls) { activityType in
                        guard let activityType else { return }
                        coordinator.handoffDidComplete(receivingBundleIdentifier: activityType)
                    }
                }
            )
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
    /// Lets a Play tap on this screen hand the ROM to the configured external app.
    func externalPlayHandoff(_ coordinator: ExternalPlayCoordinator) -> some View {
        modifier(ExternalPlayHandoffModifier(coordinator: coordinator))
    }
}
