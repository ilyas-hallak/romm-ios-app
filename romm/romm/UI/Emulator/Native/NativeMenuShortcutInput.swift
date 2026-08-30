import DeltaCore
import GameController

/// Watches a physical controller for the configured menu shortcut combo and
/// reports it to the native (DeltaCore) session.
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
/// face-button swap is deliberately not applied either: it only rewrites A/B and
/// X/Y, which no shortcut uses, so the receiver survives a swap untouched.
///
/// L3/R3 is the exception. `MFiGameController` never installs a handler for the
/// two thumbstick clicks, so they never enter the mapping and no `.deltamapping`
/// in the vendored cores can emit `l3`/`r3`. Those two buttons are read straight
/// off the `GCController`, which takes nothing away from DeltaCore precisely
/// because it ignores them.
@MainActor
final class NativeMenuShortcutInput: NSObject, GameControllerReceiver {

    /// Fired once the configured combo is complete. DeltaCore's own `.menu`
    /// input reaches the session on its own path and is never part of a combo,
    /// so the two cannot trigger each other.
    var onMenuRequested: (() -> Void)?

    private let menuShortcutPreference: PEmulatorMenuShortcutPreference?

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

    init(menuShortcutPreference: PEmulatorMenuShortcutPreference?) {
        self.menuShortcutPreference = menuShortcutPreference
        self.comboButtons = Self.comboButtons(for: menuShortcutPreference?.current ?? .none)
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
    }

    /// Picks up a shortcut changed in the in-game menu, live. Only the combo is
    /// re-read, nothing about the running core has to be touched. The latch is
    /// cleared so a button still held from the old combo cannot suppress the
    /// first press of the new one.
    func reloadPreferences() {
        comboButtons = Self.comboButtons(for: menuShortcutPreference?.current ?? .none)
        comboLatched = false
    }

    // MARK: - GameControllerReceiver

    // DeltaCore delivers on whichever queue the controller uses, which is
    // GameController's default of `.main`: its own `GameViewController` reads
    // `view.window` straight out of these methods, so main is the contract here.

    nonisolated func gameController(_ gameController: GameController, didActivate input: Input, value: Double) {
        guard let button = Self.shortcutButton(for: input) else { return }
        MainActor.assumeIsolated {
            self.set(button, pressed: true)
        }
    }

    nonisolated func gameController(_ gameController: GameController, didDeactivate input: Input) {
        guard let button = Self.shortcutButton(for: input) else { return }
        MainActor.assumeIsolated {
            self.set(button, pressed: false)
        }
    }

    // MARK: - Private helpers

    /// The standard input behind a delivered input, or `nil` when it cannot take
    /// part in a combo. Analog sticks are dropped here: they are continuous and
    /// would churn the pressed set several times a frame for nothing.
    private nonisolated static func shortcutButton(for input: Input) -> StandardGameControllerInput? {
        guard let button = StandardGameControllerInput(input: input) else { return nil }
        guard !button.isContinuous else { return nil }
        return button
    }

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
        updateMenuCombo()
    }

    /// Fires `onMenuRequested` once when every button of the configured combo is
    /// held. The buttons keep going to the core through the receivers registered
    /// alongside this one, the combo is purely additive.
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

    private static func comboButtons(for shortcut: EmulatorMenuShortcut) -> Set<StandardGameControllerInput> {
        switch shortcut {
        case .none: return []
        case .l3r3: return [.l3, .r3]
        case .l1r1: return [.l1, .r1]
        }
    }
}
