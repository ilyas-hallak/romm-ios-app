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
@MainActor
final class LibretroControllerInput {

    private weak var frontend: LibretroFrontend?
    var onMenuRequested: (() -> Void)?

    init(frontend: LibretroFrontend) {
        self.frontend = frontend
    }

    // MARK: - Connect / Disconnect

    /// Installs value-changed handlers on the given controller's extended gamepad.
    /// Safe to call with nil (no-op) so callers don't need an extra guard.
    func attach(to controller: GCController?) {
        guard let pad = controller?.extendedGamepad else { return }

        // D-Pad
        pad.dpad.up.valueChangedHandler    = { [weak self] _, _, pressed in self?.send(.up,     pressed: pressed) }
        pad.dpad.down.valueChangedHandler  = { [weak self] _, _, pressed in self?.send(.down,   pressed: pressed) }
        pad.dpad.left.valueChangedHandler  = { [weak self] _, _, pressed in self?.send(.left,   pressed: pressed) }
        pad.dpad.right.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.right,  pressed: pressed) }

        // Face buttons (SNES/libretro layout: bottom = B, right = A, left = Y, top = X)
        // GCController uses Xbox names: buttonA = bottom, buttonB = right,
        // buttonX = left, buttonY = top.
        pad.buttonA.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.b, pressed: pressed) }
        pad.buttonB.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.a, pressed: pressed) }
        pad.buttonX.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.y, pressed: pressed) }
        pad.buttonY.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.x, pressed: pressed) }

        // Shoulders
        pad.leftShoulder.valueChangedHandler  = { [weak self] _, _, pressed in self?.send(.l,  pressed: pressed) }
        pad.rightShoulder.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.r,  pressed: pressed) }

        // Triggers — treated as digital buttons, value ignored.
        pad.leftTrigger.valueChangedHandler  = { [weak self] _, _, pressed in self?.send(.l2, pressed: pressed) }
        pad.rightTrigger.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.r2, pressed: pressed) }

        // Thumbstick clicks (optional on some gamepads, hence pressedChangedHandler)
        pad.leftThumbstickButton?.valueChangedHandler  = { [weak self] _, _, pressed in self?.send(.l3, pressed: pressed) }
        pad.rightThumbstickButton?.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.r3, pressed: pressed) }

        // Start / Select
        // buttonMenu is always present; buttonOptions is absent on some controllers
        // (e.g. Apple TV Remote) so we fall back to nil-safe access.
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            // Menu button opens the in-game overlay instead of sending Start
            // to the core, consistent with the native Delta path.
            Task { @MainActor [weak self] in self?.onMenuRequested?() }
        }
        pad.buttonOptions?.valueChangedHandler = { [weak self] _, _, pressed in self?.send(.select, pressed: pressed) }

        // buttonHome is not part of GCExtendedGamepad and cannot be captured on
        // iOS without the entitlement, so .start has no physical mapping unless
        // buttonOptions is absent. On controllers without buttonOptions we
        // reserve no game button for Select rather than silently break a game
        // button; the user can always use the in-game menu to pause/quit.
    }

    /// Removes all handlers from the controller and clears any latched buttons.
    func detach(from controller: GCController?) {
        clearHandlers(on: controller?.extendedGamepad)
        frontend?.clearAllButtons()
    }

    // MARK: - Private helpers

    // nonisolated so GCController's background-thread handlers can call it
    // without a data-race warning. The actual state write is bounced to MainActor.
    nonisolated private func send(_ button: LibretroABI.JoypadButton, pressed: Bool) {
        Task { @MainActor [weak self] in
            self?.frontend?.setButton(button, pressed: pressed)
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
        pad.buttonMenu.pressedChangedHandler   = nil
        pad.buttonOptions?.valueChangedHandler = nil
    }
}
