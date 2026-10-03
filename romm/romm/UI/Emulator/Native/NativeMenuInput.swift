#if !APP_STORE
import DeltaCore
import GameController

/// The controller side of the in-game menu on the native (DeltaCore) engine:
/// watches for the configured shortcut combo that opens the menu, and steers
/// the menu while it is open.
///
/// The libretro engine owns the gamepad itself and can read raw buttons.
/// DeltaCore owns it here, so this hooks in as an *additional*
/// `GameControllerReceiver`: receivers sit in a map table keyed by receiver, so
/// several can watch the same controller and the ones already registered (the
/// core and the game view controller) keep receiving exactly what they did
/// before. A second `pressedChangedHandler` on a GCController button would not
/// work, there is only one per button and `MFiGameController` already holds it.
///
/// Registered with the controller's *default* mapping, which is what
/// `addReceiver(_:)` uses and what lets DeltaCore's own `GameViewController`
/// read `StandardGameControllerInput`. Registering with the game mapping instead
/// would deliver inputs already translated to the running system (`snes.a` and
/// friends), where a shoulder button is no longer recognisable as one. The
/// face-button swap is therefore not in the mapping and is applied by hand where
/// the menu needs it.
///
/// L3/R3 is the exception. `MFiGameController` never installs a handler for the
/// two thumbstick clicks, so they never enter the mapping and no `.deltamapping`
/// in the vendored cores can emit `l3`/`r3`. Those two buttons are read straight
/// off the `GCController`, which takes nothing away from DeltaCore precisely
/// because it ignores them.
@MainActor
final class NativeMenuInput: NSObject, GameControllerReceiver {

    /// Fired once the configured combo is complete. DeltaCore's own `.menu`
    /// input reaches the session on its own path and is never part of a combo,
    /// so the two cannot trigger each other.
    var onMenuRequested: (() -> Void)?

    /// Fired for every menu step while `isNavigatingMenu` is on.
    var onMenuCommand: ((EmulatorMenuCommand) -> Void)?

    /// While on, inputs become menu commands and the combo closes the menu
    /// instead of opening it. Keeping the inputs away from the core is the
    /// session's job, it unhooks the core while the menu is open.
    var isNavigatingMenu = false {
        didSet {
            stickX.reset()
            stickY.reset()
            isMenuButtonPressedInMenu = false
        }
    }

    private let menuShortcutPreference: PEmulatorMenuShortcutPreference?
    private let faceButtonPreference: PGamepadFaceButtonPreference?

    /// Buttons currently held, used to detect the menu shortcut combo.
    private var pressedButtons: Set<StandardGameControllerInput> = []
    /// Guards the combo so it fires once per press instead of on every event
    /// while the buttons stay held.
    private var comboLatched = false

    /// The configured combo, resolved here instead of on every input event: the
    /// preference sits in UserDefaults and changes at most a handful of times per
    /// session, while inputs arrive up to once a frame. Kept current by
    /// `reloadPreferences()`.
    private var comboButtons: Set<StandardGameControllerInput>
    /// Cached for the same reason as `comboButtons`.
    private var isFaceButtonSwapped: Bool

    private var stickX = EmulatorMenuStickAxis(negative: .left, positive: .right)
    private var stickY = EmulatorMenuStickAxis(negative: .down, positive: .up)
    /// Set when Menu goes down inside the menu, so only a full press there
    /// closes it. See `handleRelease(of:)`.
    private var isMenuButtonPressedInMenu = false

    init(menuShortcutPreference: PEmulatorMenuShortcutPreference?, faceButtonPreference: PGamepadFaceButtonPreference?) {
        self.menuShortcutPreference = menuShortcutPreference
        self.faceButtonPreference = faceButtonPreference
        self.comboButtons = Self.comboButtons(for: menuShortcutPreference?.current ?? .none)
        self.isFaceButtonSwapped = faceButtonPreference?.isSwapped ?? false
        super.init()
    }

    // MARK: - Connect / Disconnect

    /// Registers as an extra receiver and picks up the thumbstick clicks the
    /// DeltaCore mapping cannot deliver. Safe to call again for a controller that
    /// is already wired: the map table keys by receiver, so the entry is
    /// overwritten instead of duplicated, and the two handlers are reassigned.
    func attach(to controller: GameController) {
        controller.addReceiver(self, inputMapping: controller.defaultInputMapping)
        installThumbstickClickHandlers(on: controller)
    }

    /// Unregisters and drops any held button, so a controller that goes away
    /// mid-press cannot leave half a combo behind for the next one.
    func detach(from controller: GameController) {
        controller.removeReceiver(self)
        clearThumbstickClickHandlers(on: controller)
        reset()
    }

    /// Forgets every held button without touching the controller, for tearing the
    /// session down.
    func reset() {
        pressedButtons.removeAll()
        comboLatched = false
        isMenuButtonPressedInMenu = false
        stickX.reset()
        stickY.reset()
    }

    /// Picks up a shortcut or face-button swap changed in the in-game menu, live.
    /// The latch is cleared so a button still held from the old combo cannot
    /// suppress the first press of the new one.
    func reloadPreferences() {
        comboButtons = Self.comboButtons(for: menuShortcutPreference?.current ?? .none)
        isFaceButtonSwapped = faceButtonPreference?.isSwapped ?? false
        comboLatched = false
    }

    /// The menu step behind a button, or `nil` when it does nothing in the menu.
    /// Confirm is the button labelled A: the bottom one on an Xbox-style pad, the
    /// right one when the player has told us their labels are the other way round.
    /// Menu is left out on purpose, see `handleRelease(of:)`.
    nonisolated static func menuCommand(for button: StandardGameControllerInput, faceButtonsSwapped: Bool) -> EmulatorMenuCommand? {
        switch button {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .a: return faceButtonsSwapped ? .back : .confirm
        case .b: return faceButtonsSwapped ? .confirm : .back
        default: return nil
        }
    }

    // MARK: - GameControllerReceiver

    // DeltaCore delivers on whichever queue the controller uses, which is
    // GameController's default of `.main`: its own `GameViewController` reads
    // `view.window` straight out of these methods, so main is the contract here.

    nonisolated func gameController(_ gameController: GameController, didActivate input: Input, value: Double) {
        guard let button = StandardGameControllerInput(input: input) else { return }
        MainActor.assumeIsolated {
            if button.isContinuous {
                self.updateStick(button, value: Float(value))
            } else {
                self.set(button, pressed: true)
            }
        }
    }

    nonisolated func gameController(_ gameController: GameController, didDeactivate input: Input) {
        guard let button = StandardGameControllerInput(input: input) else { return }
        MainActor.assumeIsolated {
            if button.isContinuous {
                self.updateStick(button, value: 0)
            } else {
                self.set(button, pressed: false)
            }
        }
    }

    // MARK: - Private helpers

    /// Reads the two thumbstick clicks off the physical pad. Only `MFiGameController`
    /// has one, a keyboard controller simply has no sticks to click.
    private func installThumbstickClickHandlers(on controller: GameController) {
        guard let profile = Self.physicalInputProfile(of: controller) else { return }
        profile.buttons[GCInputLeftThumbstickButton]?.pressedChangedHandler = handler(for: .l3)
        profile.buttons[GCInputRightThumbstickButton]?.pressedChangedHandler = handler(for: .r3)
    }

    private func clearThumbstickClickHandlers(on controller: GameController) {
        guard let profile = Self.physicalInputProfile(of: controller) else { return }
        profile.buttons[GCInputLeftThumbstickButton]?.pressedChangedHandler = nil
        profile.buttons[GCInputRightThumbstickButton]?.pressedChangedHandler = nil
    }

    private static func physicalInputProfile(of controller: GameController) -> GCPhysicalInputProfile? {
        (controller as? MFiGameController)?.controller.physicalInputProfile
    }

    /// Builds a handler for one thumbstick click. `handlerQueue` is GameController's
    /// default `.main`, which is what makes the assumeIsolated sound.
    private func handler(for button: StandardGameControllerInput) -> GCControllerButtonValueChangedHandler {
        return { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                self?.set(button, pressed: pressed)
            }
        }
    }

    private func set(_ button: StandardGameControllerInput, pressed: Bool) {
        if pressed {
            pressedButtons.insert(button)
        } else {
            pressedButtons.remove(button)
        }
        if isNavigatingMenu {
            if pressed {
                handlePress(of: button)
            } else {
                handleRelease(of: button)
            }
        }
        updateMenuCombo()
    }

    private func handlePress(of button: StandardGameControllerInput) {
        if button == .menu {
            isMenuButtonPressedInMenu = true
        }
        guard let command = Self.menuCommand(for: button, faceButtonsSwapped: isFaceButtonSwapped) else { return }
        onMenuCommand?(command)
    }

    /// Menu closes on release, not on press. DeltaCore's `GameViewController`
    /// opens the menu on the release of the same button, and it is back in the
    /// receiver list by then: closing on the press would reopen the menu at once.
    /// The press has to have happened inside the menu too, otherwise the release
    /// that just opened it could close it again.
    private func handleRelease(of button: StandardGameControllerInput) {
        guard button == .menu, isMenuButtonPressedInMenu else { return }
        isMenuButtonPressedInMenu = false
        onMenuCommand?(.back)
    }

    /// The left stick steps through the menu like the D-pad. The right stick is
    /// left alone, it is too easy to brush while reaching for the face buttons.
    private func updateStick(_ input: StandardGameControllerInput, value: Float) {
        guard isNavigatingMenu else { return }
        let command: EmulatorMenuCommand?
        switch input {
        case .leftThumbstickLeft: command = stickX.update(half: .negative, magnitude: value)
        case .leftThumbstickRight: command = stickX.update(half: .positive, magnitude: value)
        case .leftThumbstickDown: command = stickY.update(half: .negative, magnitude: value)
        case .leftThumbstickUp: command = stickY.update(half: .positive, magnitude: value)
        default: command = nil
        }
        if let command {
            onMenuCommand?(command)
        }
    }

    /// Fires once when every button of the configured combo is held. Outside the
    /// menu it opens it, and the buttons keep going to the core through the
    /// receivers registered alongside this one. Inside the menu it closes it, so
    /// the same shortcut works both ways.
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

    private static func comboButtons(for shortcut: EmulatorMenuShortcut) -> Set<StandardGameControllerInput> {
        switch shortcut {
        case .none: return []
        case .l3r3: return [.l3, .r3]
        case .l1r1: return [.l1, .r1]
        }
    }
}
#endif
