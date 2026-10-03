import GameController

/// Bridges one connected GCController to one libretro player.
///
/// Maps digital buttons and D-Pad only. Analog sticks never reach the core,
/// the left one only steps through the in-game menu.
///
/// Layout follows the SNES/libretro convention where the bottom face button
/// is RETRO_DEVICE_ID_JOYPAD_B (index 0) and the right face button is
/// RETRO_DEVICE_ID_JOYPAD_A (index 8), so physical A/B and X/Y are
/// cross-mapped from the Xbox-style GCController naming to the SNES layout.
/// `PGamepadFaceButtonPreference` flips those two pairs back for pads whose
/// labels run the other way round.
///
/// Writes go straight to the frontend's button state from the handler, exactly
/// like the touch path in LibretroTouchControllerView. The core reads that array from the
/// emulation thread; that is a pre-existing, deliberate arrangement here and
/// this class does not add synchronisation of its own.
@MainActor
final class LibretroControllerInput {

    private weak var frontend: LibretroFrontend?
    /// Libretro port this pad drives.
    private let player: Int
    private let menuShortcutPreference: PEmulatorMenuShortcutPreference?
    private let faceButtonPreference: PGamepadFaceButtonPreference?
    var onMenuRequested: (() -> Void)?

    /// Fired for every menu step while `isNavigatingMenu` is on.
    var onMenuCommand: ((EmulatorMenuCommand) -> Void)?

    /// While on, the pad steers the in-game menu and nothing reaches the core,
    /// which would otherwise still read the buttons while paused. Turning it on
    /// lifts whatever was held, so no button is left stuck down in the core.
    var isNavigatingMenu = false {
        didSet {
            guard isNavigatingMenu != oldValue else { return }
            stickX.reset()
            stickY.reset()
            if isNavigatingMenu {
                frontend?.clearAllButtons(player: player)
            }
        }
    }

    private var stickX = EmulatorMenuStickAxis(negative: .left, positive: .right)
    private var stickY = EmulatorMenuStickAxis(negative: .down, positive: .up)

    /// Digital buttons currently held, used to detect the menu shortcut combo.
    private var pressedButtons: Set<LibretroABI.JoypadButton> = []
    /// Guards the combo so it fires once per press instead of on every event
    /// while the buttons stay held.
    private var comboLatched = false

    /// The configured combo, resolved here instead of on every button event: the
    /// preference sits in UserDefaults and changes at most a handful of times per
    /// session, while `send` runs up to once a frame. Kept current by
    /// `reloadPreferences(for:)`.
    private var comboButtons: Set<LibretroABI.JoypadButton>

    init(
        frontend: LibretroFrontend,
        player: Int = 0,
        menuShortcutPreference: PEmulatorMenuShortcutPreference? = nil,
        faceButtonPreference: PGamepadFaceButtonPreference? = nil
    ) {
        self.frontend = frontend
        self.player = player
        self.menuShortcutPreference = menuShortcutPreference
        self.faceButtonPreference = faceButtonPreference
        self.comboButtons = Self.comboButtons(for: menuShortcutPreference?.current ?? .none)
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

        installFaceButtonHandlers(on: pad)

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

        // The core never sees the stick, it only steps through the menu.
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated {
                self?.updateStick(x: x, y: y)
            }
        }
    }

    /// Picks up the face-button swap and the menu shortcut after they changed in
    /// the in-game menu, without restarting the core. Rebinding the four face
    /// handlers is what makes the swap live: the alternative, resolving the
    /// preference inside every handler, would pay a UserDefaults read per button
    /// event for a value that hardly ever changes.
    func reloadPreferences(for controller: GCController?) {
        comboButtons = Self.comboButtons(for: menuShortcutPreference?.current ?? .none)
        // A face button held while the swap lands would send its release to the
        // newly mapped button and leave the old one stuck down in the core.
        releaseFaceButtons()
        guard let pad = controller?.extendedGamepad else { return }
        installFaceButtonHandlers(on: pad)
    }

    /// Removes all handlers from the controller and clears any latched buttons.
    func detach(from controller: GCController?) {
        clearHandlers(on: controller?.extendedGamepad)
        pressedButtons.removeAll()
        comboLatched = false
        stickX.reset()
        stickY.reset()
        frontend?.clearAllButtons(player: player)
    }

    /// The menu step behind a libretro button, or `nil` when it does nothing in
    /// the menu. Confirm is `.b` whichever way the face buttons are swapped: the
    /// swap exists so that `.b` always lands on the button labelled A.
    nonisolated static func menuCommand(for button: LibretroABI.JoypadButton) -> EmulatorMenuCommand? {
        switch button {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .b: return .confirm
        case .a, .start: return .back
        default: return nil
        }
    }

    // MARK: - Face button layout

    /// Where a face button sits on the pad, independent of what is printed on it.
    enum FaceButtonPosition {
        case bottom, right, left, top
    }

    /// The libretro button a physical face button drives. `swapped` exchanges
    /// the two pairs for pads whose labels run the other way round.
    nonisolated static func faceButton(_ position: FaceButtonPosition, swapped: Bool) -> LibretroABI.JoypadButton {
        switch position {
        case .bottom: return swapped ? .a : .b
        case .right:  return swapped ? .b : .a
        case .left:   return swapped ? .x : .y
        case .top:    return swapped ? .y : .x
        }
    }

    // MARK: - Private helpers

    /// Face buttons (SNES/libretro layout: bottom = B, right = A, left = Y, top = X).
    /// GCController uses Xbox names: buttonA = bottom, buttonB = right,
    /// buttonX = left, buttonY = top. The pairs flip when the player has told us
    /// their pad is labelled the other way round.
    private func installFaceButtonHandlers(on pad: GCExtendedGamepad) {
        let swapped = faceButtonPreference?.isSwapped ?? false
        pad.buttonA.valueChangedHandler = handler(for: Self.faceButton(.bottom, swapped: swapped))
        pad.buttonB.valueChangedHandler = handler(for: Self.faceButton(.right, swapped: swapped))
        pad.buttonX.valueChangedHandler = handler(for: Self.faceButton(.left, swapped: swapped))
        pad.buttonY.valueChangedHandler = handler(for: Self.faceButton(.top, swapped: swapped))
    }

    /// Lifts all four face buttons in the core, whichever way round they are
    /// currently mapped.
    private func releaseFaceButtons() {
        for button in [LibretroABI.JoypadButton.a, .b, .x, .y] {
            send(button, pressed: false)
        }
    }

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
        if isNavigatingMenu {
            if pressed, let command = Self.menuCommand(for: button) {
                onMenuCommand?(command)
            }
        } else {
            frontend?.setButton(button, pressed: pressed, player: player)
        }
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
        if isNavigatingMenu {
            onMenuCommand?(.back)
        } else {
            onMenuRequested?()
        }
    }

    private func updateStick(x: Float, y: Float) {
        guard isNavigatingMenu else { return }
        for command in [stickX.update(x), stickY.update(y)].compactMap({ $0 }) {
            onMenuCommand?(command)
        }
    }

    private static func comboButtons(for shortcut: EmulatorMenuShortcut) -> Set<LibretroABI.JoypadButton> {
        switch shortcut {
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
        pad.leftThumbstick.valueChangedHandler = nil
        pad.leftThumbstickButton?.valueChangedHandler  = nil
        pad.rightThumbstickButton?.valueChangedHandler = nil
        pad.buttonMenu.valueChangedHandler     = nil
        pad.buttonOptions?.valueChangedHandler = nil
    }
}
