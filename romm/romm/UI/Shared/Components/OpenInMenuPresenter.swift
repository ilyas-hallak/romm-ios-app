import SwiftUI
import UIKit

/// A single ROM file on its way to another app.
struct OpenInItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    /// Temp directory holding the copy that was handed over.
    let tempDirectory: URL?
}

/// Presents the system "Open in" menu for a single file.
///
/// Unlike `UIActivityViewController` this lists only apps that can actually open
/// the document, which is what handing a ROM to an emulator should offer — no
/// Mail, AirDrop or Save to Files in between. It also reports the receiving
/// bundle identifier, the only reliable signal that the handoff happened.
///
/// Place it in a `.background()` of the control that triggers it: the anchor rect
/// for the iPad popover is then the control itself.
struct OpenInMenuPresenter: UIViewRepresentable {
    /// Set to a value to present the menu, back to nil to reset.
    let item: OpenInItem?
    /// Bundle identifier of the app the file was sent to.
    let onSent: (String) -> Void
    /// Menu closed, either after sending or by cancelling.
    let onDismiss: () -> Void
    /// No installed app can open this file type.
    let onNoTargets: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSent = onSent
        coordinator.onDismiss = onDismiss
        coordinator.onNoTargets = onNoTargets

        guard let item else {
            coordinator.reset()
            return
        }
        // The view has just been handed to SwiftUI and may not be in a window
        // yet; presenting from a window-less view silently fails.
        DispatchQueue.main.async {
            coordinator.present(item, from: uiView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentInteractionControllerDelegate {
        var onSent: ((String) -> Void)?
        var onDismiss: (() -> Void)?
        var onNoTargets: (() -> Void)?

        /// `UIDocumentInteractionController` is not retained by UIKit while the
        /// menu is up, so it has to be held here.
        private var controller: UIDocumentInteractionController?
        private var presentedItemID: UUID?

        func present(_ item: OpenInItem, from view: UIView) {
            guard presentedItemID != item.id, view.window != nil else { return }
            presentedItemID = item.id

            let controller = UIDocumentInteractionController(url: item.url)
            controller.delegate = self
            self.controller = controller

            if !controller.presentOpenInMenu(from: view.bounds, in: view, animated: true) {
                self.controller = nil
                onNoTargets?()
            }
        }

        func reset() {
            presentedItemID = nil
            controller = nil
        }

        nonisolated func documentInteractionController(
            _ controller: UIDocumentInteractionController,
            didEndSendingToApplication application: String?
        ) {
            guard let application else { return }
            MainActor.assumeIsolated { onSent?(application) }
        }

        nonisolated func documentInteractionControllerDidDismissOpenInMenu(
            _ controller: UIDocumentInteractionController
        ) {
            MainActor.assumeIsolated {
                self.controller = nil
                onDismiss?()
            }
        }
    }
}
