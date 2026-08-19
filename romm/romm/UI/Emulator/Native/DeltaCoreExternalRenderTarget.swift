import UIKit
import DeltaCore

/// Sends a DeltaCore game to an external display.
///
/// DeltaCore is built for this: an `EmulatorCore` hands every frame to each
/// `GameView` registered with its `VideoManager`, so a second one costs one more
/// draw of an image that already exists rather than a second emulation pass.
@MainActor
final class DeltaCoreExternalRenderTarget: PExternalRenderTarget {

    private weak var core: EmulatorCore?
    private weak var surface: PExternalDisplaySurface?
    private var screen: ExternalGameScreenView?

    init(core: EmulatorCore) {
        self.core = core
    }

    func startRendering(into surface: PExternalDisplaySurface) {
        guard screen == nil, let core else { return }
        let screen = ExternalGameScreenView()
        screen.renderingSize = core.preferredRenderingSize
        core.add(screen.gameView)
        surface.setContent(screen)
        self.screen = screen
        self.surface = surface
        print("[Native] rendering to the external display at \(Int(core.preferredRenderingSize.width))x\(Int(core.preferredRenderingSize.height))")
    }

    func stopRendering() {
        guard let screen else { return }
        // Unregister before dropping the view: the core must never keep a render
        // target that is no longer on screen.
        core?.remove(screen.gameView)
        surface?.setContent(nil)
        self.screen = nil
    }
}
