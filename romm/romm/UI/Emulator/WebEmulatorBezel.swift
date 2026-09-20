import SwiftUI

/// Handheld style frame around the web emulator.
///
/// EmulatorJS draws the picture and its own touch buttons into one page, so the
/// frame goes around the whole web view and not around the picture alone. That
/// gives the same shell look the native engine gets from a controller skin,
/// without depending on anything inside the page.
private struct WebEmulatorBezelModifier: ViewModifier {
    private enum Metrics {
        /// Deliberately narrow. In landscape the screen is short to begin with,
        /// and every point here is one the game loses.
        static let shellPadding: CGFloat = 16
        static let screenCornerRadius: CGFloat = 12
        static let screenEdgeWidth: CGFloat = 1
    }

    func body(content: Content) -> some View {
        content
            .clipShape(screenShape)
            .overlay(screenEdge)
            .shadow(color: .black.opacity(0.7), radius: 6, y: 2)
            .padding(Metrics.shellPadding)
            .background(shell)
    }

    private var screenShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.screenCornerRadius, style: .continuous)
    }

    /// Thin light line along the cut out, which is what makes the screen read as
    /// sunk into the shell rather than pasted on top of it.
    private var screenEdge: some View {
        screenShape.strokeBorder(Color.white.opacity(0.22), lineWidth: Metrics.screenEdgeWidth)
    }

    /// Plain dark plastic. A gradient only, no device art: the app has no shell
    /// artwork per platform, and a neutral frame suits every console.
    private var shell: some View {
        LinearGradient(
            colors: [Color(white: 0.26), Color(white: 0.11)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// Frames the web emulator like a handheld. Turned off, the view is passed
    /// through untouched, so the layout stays exactly as it was.
    @ViewBuilder
    func webEmulatorBezel(isEnabled: Bool) -> some View {
        if isEnabled {
            modifier(WebEmulatorBezelModifier())
        } else {
            self
        }
    }
}
