import SwiftUI

/// The pad itself, drawn by the same view the in-app touch controls use, so a
/// player finds the buttons where they already know them.
struct RemoteGamepadView: UIViewRepresentable {

    let onButton: (RemoteGamepadButton, Bool) -> Void

    func makeUIView(context: Context) -> LibretroTouchControllerView {
        let view = LibretroTouchControllerView()
        // No game runs on this phone, so there is nothing to pause.
        view.isMenuButtonHidden = true
        view.onButton = { libretroButton, pressed in
            guard let button = RemoteGamepadButton(libretroButton: libretroButton) else { return }
            onButton(button, pressed)
        }
        return view
    }

    func updateUIView(_ uiView: LibretroTouchControllerView, context: Context) {
        uiView.onButton = { libretroButton, pressed in
            guard let button = RemoteGamepadButton(libretroButton: libretroButton) else { return }
            onButton(button, pressed)
        }
    }
}
