#if !APP_STORE
import SwiftUI
import DeltaCore

/// A Delta skin the pad can draw, wrapped so the SwiftUI screen around it does
/// not import DeltaCore, whose `State` would shadow SwiftUI's.
struct RemotePadSkin {

    fileprivate let skin: ControllerSkin

    /// `nil` for the generic pad, and for a system this phone does not know,
    /// which then gets the generic pad as well.
    init?(layout: RemotePadLayout) {
        guard case .deltaSkin(let identifier) = layout,
              let skin = ControllerSkin.standardControllerSkin(for: GameType(rawValue: identifier)) else { return nil }
        self.skin = skin
    }
}

/// The pad as the host's own phone would draw it: the standard Delta skin of the
/// system the host runs, so an N64 game gets its stick and C buttons.
///
/// `ControllerView` needs no running core to draw a skin and report its inputs,
/// only the skin itself. The skin's menu button has no game to pause here, so
/// it is reported on its own.
struct DeltaSkinPadView: UIViewRepresentable {

    let skin: RemotePadSkin
    let onInput: (String, Double) -> Void
    let onMenu: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SkinContainerView {
        let view = SkinContainerView()
        view.controllerView.addReceiver(context.coordinator, inputMapping: nil)
        return view
    }

    func updateUIView(_ uiView: SkinContainerView, context: Context) {
        context.coordinator.onInput = onInput
        context.coordinator.onMenu = onMenu
        if uiView.controllerView.controllerSkin?.identifier != skin.skin.identifier {
            uiView.controllerView.controllerSkin = skin.skin
        }
    }

    /// Hands the skin's inputs on by name, the names are what the host resolves.
    final class Coordinator: NSObject, GameControllerReceiver {

        var onInput: (String, Double) -> Void = { _, _ in }
        var onMenu: () -> Void = {}

        func gameController(_ gameController: GameController, didActivate input: Input, value: Double) {
            if input.stringValue == StandardGameControllerInput.menu.stringValue {
                onMenu()
            } else {
                onInput(input.stringValue, value)
            }
        }

        func gameController(_ gameController: GameController, didDeactivate input: Input) {
            guard input.stringValue != StandardGameControllerInput.menu.stringValue else { return }
            onInput(input.stringValue, 0)
        }
    }

    /// DeltaCore only picks the skin's image and item frames for the size it
    /// lays out at, so the skin is set again whenever the size changes. It also
    /// builds the skin in one layout pass and places the items in the next, and
    /// a view that arrives at its final size gets only one, which leaves the
    /// thumbstick at zero size. Both passes are run here.
    final class SkinContainerView: UIView {

        let controllerView = ControllerView()
        private var laidOutSize: CGSize = .zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            controllerView.frame = bounds
            controllerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(controllerView)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.size != laidOutSize else { return }
            laidOutSize = bounds.size
            controllerView.layoutIfNeeded()
            let skin = controllerView.controllerSkin
            controllerView.controllerSkin = skin
            controllerView.layoutIfNeeded()
        }
    }
}
#endif
