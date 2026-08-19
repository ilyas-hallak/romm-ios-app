import UIKit

/// The surface a renderer paints when the app owns an external display.
///
/// Two shapes, because the two emulator backends differ in kind: libretro
/// produces a finished `CGImage` per frame, which is simply assigned to a layer,
/// while DeltaCore hands its frames to views that render themselves.
@MainActor
protocol PExternalDisplaySurface: AnyObject {

    /// For renderers that blit finished images.
    var videoLayer: CALayer { get }

    /// For renderers that bring their own view. Pass `nil` to clear.
    func setContent(_ view: UIView?)
}

/// A renderer's end of the arrangement.
///
/// The display manager knows *when* the app owns the display, a render target
/// knows *how* to paint. Keeping those apart is what lets a third backend be
/// added later without touching scene and window handling, and it is why neither
/// side has to reach for the other's internals any more.
@MainActor
protocol PExternalRenderTarget: AnyObject {

    /// Called when the app takes the display over. May be called again after a
    /// `stopRendering`, for instance when the player toggles Play on TV twice.
    func startRendering(into surface: PExternalDisplaySurface)

    /// Called when the display goes back to plain mirroring, or the session ends.
    /// Must leave nothing of the renderer registered on the surface.
    func stopRendering()
}
