import SwiftUI

/// The Share entry in a downloaded ROM's leading swipe actions.
///
/// Deliberately holds no presentation of its own. A swipe action's button is
/// torn out of the hierarchy the moment the row snaps shut, so a `.sheet`
/// attached to it is dismissed in the same run loop it was asked to appear in,
/// and nothing ever shows. The list owns the sheet instead.
struct ShareSwipeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
    }
}
