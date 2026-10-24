#if !APP_STORE
import SwiftUI

/// Adapts Delta 2.0's pause-menu division placement to RomM's save-state sheet.
/// Original approach: Riley Testut, Copyright 2026.
struct DuoMenuRegion<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            if #available(iOS 27.1, *), horizontalSizeClass == .regular,
               let division = geometry.reservedRegions(kind: .division).first {
                let isHorizontal = division.frame.width > division.frame.height
                let primarySize = CGSize(
                    width: isHorizontal ? geometry.size.width : max(0, division.frame.minX),
                    height: isHorizontal ? max(0, division.frame.minY) : geometry.size.height
                )
                ArrangementView {
                    Color.clear
                        .frame(width: primarySize.width, height: primarySize.height)
                        .splitArrangementFixedLayoutSize()
                        .accessibilityHidden(true)
                } secondary: {
                    content
                }
                .arrangementViewStyle(.split)
            } else {
                content
            }
        }
    }
}
#endif
