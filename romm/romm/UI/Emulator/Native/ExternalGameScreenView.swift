import UIKit
import AVFoundation
import DeltaCore

/// Shows a DeltaCore game on an external display.
///
/// DeltaCore is built for this: an `EmulatorCore` hands every frame to each
/// `GameView` registered with its `VideoManager`, so a second one costs one more
/// draw of an image that already exists rather than a second emulation pass.
/// This view owns that extra `GameView` and does nothing but letterbox it, since
/// a TV's aspect ratio has no relation to a console's.
///
/// No filter is set on the game view on purpose. The on-screen views get crop
/// filters from the controller skin, which is how a dual-screen system like the
/// DS is split into two panes on the phone. Leaving it unfiltered means the TV
/// shows the core's framebuffer as it is, which for the DS is both screens
/// stacked, the same thing the phone shows once the touch skin is hidden.
final class ExternalGameScreenView: UIView {

    let gameView = GameView(frame: .zero)

    /// The core's framebuffer size, used purely for the aspect ratio.
    var renderingSize: CGSize = .zero {
        didSet {
            guard renderingSize != oldValue else { return }
            setNeedsLayout()
        }
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        // Blowing a 240p console up to 4K with bilinear smearing looks like a
        // washed out mess; nearest keeps the pixels as pixels.
        gameView.samplerMode = .nearestNeighbor
        addSubview(gameView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0,
              renderingSize.width > 0, renderingSize.height > 0 else { return }
        gameView.frame = AVMakeRect(aspectRatio: renderingSize, insideRect: bounds).integral
    }
}
