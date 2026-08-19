import GameController

/// Bridges a connected GCController to LibretroFrontend.buttonState.
///
/// Maps digital buttons and D-Pad only. Analog sticks are intentionally
/// omitted, they may be added in a future iteration if needed.
///
/// Layout follows the SNES/libretro convention where the bottom face button
/// is RETRO_DEVICE_ID_JOYPAD_B (index 0) and the right face button is
/// RETRO_DEVICE_ID_JOYPAD_A (index 8), so physical A/B and X/Y are
/// cross-mapped from the Xbox-style GCController naming to the SNES layout.
///
/// Writes go straight to `buttonState` from the handler, exactly like the touch
/// path in LibretroTouchControllerView. The core reads that array from the
/// emulation thread; that is a pre-existing, deliberate arrangement here and
/// this class does not add synchronisation of its own.
@MainActor
final class LibretroControllerInput {

    private weak var frontend: LibretroFrontend?
    private let menuShortcutPreference: PEmulatorMenuShortcutPreference?
    var onMenuRequested: (() -> Void)?

    /// Digital buttons currently held, used to detect the menu shortcut combo.
    private var pressedButtons: Set<LibretroABI.JoypadButton> = []
    /// Guards the combo so it fires once per press instead of on every event
    /// while the buttons stay held.
    private var comboLatched = false

    init(frontend: LibretroFrontend, menuShortcutPreference: PEmulatorMenuShortcutPreference? = nil) {
        self.frontend = frontend
        self.menuShortcutPreference = menuShortcutPreference
    }

    // MARK: - Connect / Disconnect

    /// Installs value-changed handlers on the given controller's extended gamepad.
    /// Safe to call with nil (no-op) so callers don't need an extra guard.
    func attach(to controller: GCController?) {
        guard let controller, let pad = controller.extendedGamepad else { return }

        // Pin handler delivery to the main queue. This is GameController's
        // default, but making it explicit is what lets the handlers below write
        // buttonState synchronously without an actor hop.
        controller.handlerQueue = .main

        // D-Pad
        pad.dpad.up.valueChangedHandler    = handler(for: .up)
        pad.dpad.down.valueChangedHandler  = handler(for: .down)
        pad.dpad.left.valueChangedHandler  = handler(for: .left)
        pad.dpad.right.valueChangedHandler = handler(for: .right)

        // Face buttons (SNES/libretro layout: bottom = B, right = A, left = Y, top = X)
        // GCController uses Xbox names: buttonA = bottom, buttonB = right,
        // buttonX = left, buttonY = top.
        pad.buttonA.valueChangedHandler = handler(for: .b)
        pad.buttonB.valueChangedHandler = handler(for: .a)
        pad.buttonX.valueChangedHandler = handler(for: .y)
        pad.buttonY.valueChangedHandler = handler(for: .x)

        // Shoulders
        pad.leftShoulder.valueChangedHandler  = handler(for: .l)
        pad.rightShoulder.valueChangedHandler = handler(for: .r)

        // Triggers, treated as digital buttons, analog value ignored.
        pad.leftTrigger.valueChangedHandler  = handler(for: .l2)
        pad.rightTrigger.valueChangedHandler = handler(for: .r2)

        // Thumbstick clicks are absent on some gamepads, hence the optional chain.
        pad.leftThumbstickButton?.valueChangedHandler  = handler(for: .l3)
        pad.rightThumbstickButton?.valueChangedHandler = handler(for: .r3)

        // Start / Select. buttonMenu is always present on an extended gamepad and
        // carries Start, which most PS1 titles need to get past their title
        // screen. buttonOptions is absent on some controllers, those simply have
        // no Select. The in-game menu is reached via the on-screen menu button
        // that appears whenever the touch controls hide, or via the optional
        // shortcut combo below.
        pad.buttonMenu.valueChangedHandler = handler(for: .start)
        pad.buttonOptions?.valueChangedHandler = handler(for: .select)
    }

    /// Removes all handlers from the controller and clears any latched buttons.
    func detach(from controller: GCController?) {
        clearHandlers(on: controller?.extendedGamepad)
        pressedButtons.removeAll()
        comboLatched = false
        frontend?.clearAllButtons()
    }

    // MARK: - Private helpers

    /// Builds a handler that forwards one physical button to one libretro button.
    /// `handlerQueue` is pinned to `.main` in `attach`, so the assumeIsolated is
    /// sound and keeps the write on the same runloop turn as the input event.
    private func handler(for button: LibretroABI.JoypadButton) -> GCControllerButtonValueChangedHandler {
        return { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                self?.send(button, pressed: pressed)
            }
        }
    }

    private func send(_ button: LibretroABI.JoypadButton, pressed: Bool) {
        frontend?.setButton(button, pressed: pressed)
        if pressed {
            pressedButtons.insert(button)
        } else {
            pressedButtons.remove(button)
        }
        updateMenuCombo()
    }

    /// Fires `onMenuRequested` once when every button of the configured combo is
    /// held. The buttons keep going to the core as normal, the combo is purely
    /// additive.
    private func updateMenuCombo() {
        let combo = comboButtons
        guard !combo.isEmpty else {
            comboLatched = false
            return
        }
        guard combo.isSubset(of: pressedButtons) else {
            comboLatched = false
            return
        }
        guard !comboLatched else { return }
        comboLatched = true
        onMenuRequested?()
    }

    private var comboButtons: Set<LibretroABI.JoypadButton> {
        switch menuShortcutPreference?.current ?? .none {
        case .none: return []
        case .l3r3: return [.l3, .r3]
        case .l1r1: return [.l, .r]
        }
    }

    private func clearHandlers(on pad: GCExtendedGamepad?) {
        guard let pad else { return }
        pad.dpad.up.valueChangedHandler    = nil
        pad.dpad.down.valueChangedHandler  = nil
        pad.dpad.left.valueChangedHandler  = nil
        pad.dpad.right.valueChangedHandler = nil
        pad.buttonA.valueChangedHandler    = nil
        pad.buttonB.valueChangedHandler    = nil
        pad.buttonX.valueChangedHandler    = nil
        pad.buttonY.valueChangedHandler    = nil
        pad.leftShoulder.valueChangedHandler  = nil
        pad.rightShoulder.valueChangedHandler = nil
        pad.leftTrigger.valueChangedHandler   = nil
        pad.rightTrigger.valueChangedHandler  = nil
        pad.leftThumbstickButton?.valueChangedHandler  = nil
        pad.rightThumbstickButton?.valueChangedHandler = nil
        pad.buttonMenu.valueChangedHandler     = nil
        pad.buttonOptions?.valueChangedHandler = nil
    }
}
