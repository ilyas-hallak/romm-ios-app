import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Shared component for presenting iOS share sheet
struct ShareSheet: UIViewControllerRepresentable {
    private let logger = Logger.ui

    let activityItems: [Any]
    /// Called with the activity that handled the share. For "Open in <app>" this
    /// is the receiving bundle identifier, which is how a handoff is confirmed.
    var onCompleted: ((String?) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Convert URLs to NSURL file URLs for better compatibility
        var filesToShare = [Any]()

        for item in activityItems {
            if let url = item as? URL {
                // Create NSURL with fileURLWithPath for proper file sharing
                filesToShare.append(NSURL(fileURLWithPath: url.path))
            } else {
                logger.warning("Ignoring non-URL share item of type \(type(of: item))")
            }
        }

        logger.debug("Sharing \(filesToShare.count) file(s)")

        let controller = UIActivityViewController(
            activityItems: filesToShare,
            applicationActivities: nil
        )

        // For iPad: configure popover presentation
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.permittedArrowDirections = .any
        }

        // Be notified of the result when the share sheet is dismissed
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            if let error {
                logger.error("Share failed: \(error.localizedDescription)")
            } else if completed {
                logger.info("Share completed with \(activityType?.rawValue ?? "unknown")")
                onCompleted?(activityType?.rawValue)
            } else {
                logger.debug("Share cancelled")
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
