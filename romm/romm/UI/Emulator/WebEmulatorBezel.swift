import SwiftUI

/// Handheld style frame around the web emulator.
///
/// EmulatorJS draws the picture and its own touch buttons into one page, so the
/// frame goes around the whole web view and not around the picture alone. That
/// gives the same shell look the native engine gets from a controller skin,
/// without depending on anything inside the page.
private struct WebEmulatorBezelModifier: ViewModifier {
    let platformSlug: String?

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum Metrics {
        /// Deliberately narrow. In landscape the screen is short to begin with,
        /// and every point here is one the game loses.
        static let shellPadding: CGFloat = 16
        static let screenCornerRadius: CGFloat = 12
        static let screenEdgeWidth: CGFloat = 1
        static let logoSpacing: CGFloat = 8
        static let logoHeight: CGFloat = 26
        /// Landscape on a phone is short, so the chin below the screen carries a
        /// smaller logo there.
        static let compactLogoHeight: CGFloat = 16
    }

    func body(content: Content) -> some View {
        VStack(spacing: Metrics.logoSpacing) {
            content
                .clipShape(screenShape)
                .overlay(screenEdge)
                .shadow(color: .black.opacity(0.7), radius: 6, y: 2)

            logo
        }
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

    /// The console the game belongs to, printed on the chin the way a handheld
    /// carries its own name. Dimmed, it decorates the shell and must not pull
    /// the eye away from the game.
    ///
    /// Left out when the catalog has no icon for the platform, the generic
    /// placeholder says nothing and would only cost screen space.
    @ViewBuilder
    private var logo: some View {
        if PlatformIcon.hasIcon(for: platformSlug) {
            Image(PlatformIcon.assetName(for: platformSlug))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: logoHeight)
                .opacity(0.75)
                .accessibilityHidden(true)
        }
    }

    private var logoHeight: CGFloat {
        verticalSizeClass == .compact ? Metrics.compactLogoHeight : Metrics.logoHeight
    }

    /// Plain dark plastic, the platform icon is the only decoration on it.
    private var shell: some View {
        LinearGradient(
            colors: [Color(white: 0.26), Color(white: 0.11)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension View {
    /// Frames the web emulator like a handheld, with the platform's icon on the
    /// shell. Turned off, the view is passed through untouched, so the layout
    /// stays exactly as it was.
    @ViewBuilder
    func webEmulatorBezel(isEnabled: Bool, platformSlug: String?) -> some View {
        if isEnabled {
            modifier(WebEmulatorBezelModifier(platformSlug: platformSlug))
        } else {
            self
        }
    }
}
