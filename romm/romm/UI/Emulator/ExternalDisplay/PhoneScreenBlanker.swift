import Foundation
import Combine

/// Blanks the phone's own screen while a game runs on a TV, so the handset can
/// go in a pocket without lighting up the room or burning battery.
///
/// iOS has no API to actually power the display down, that is only possible by
/// locking the device, which would background the app and stop emulation. What
/// is possible is brightness 0 plus an all-black view: on the OLED panels these
/// phones use, black pixels are switched off, so this lands very close to a
/// dark screen in both looks and power draw.
///
/// Deliberately mechanical: it does not decide *whether* dimming is appropriate,
/// that is `ExternalDisplayPolicy`'s job and the caller's to apply. This only
/// runs the countdown and moves the brightness.
///
/// A singleton for the same reason the display manager is one, the recovery path
/// runs from `AppDelegate` before any view exists. Its collaborators are
/// injected, so the countdown and the recovery can be tested without a device.
@MainActor
final class PhoneScreenBlanker: ObservableObject {

    static let shared = PhoneScreenBlanker(
        brightness: DefaultDependencyFactory.shared.screenBrightness,
        preference: DefaultDependencyFactory.shared.externalDisplayPreference
    )

    @Published private(set) var isBlanked = false

    /// Grace period before dimming on its own. Long enough to reach the menu
    /// button after starting a game, short enough not to sit there glowing.
    private static let autoDimDelay: TimeInterval = 8

    private let brightness: PScreenBrightness
    private let preference: PExternalDisplayPreference

    private var autoDimTimer: Timer?
    /// True while the caller says the conditions hold: game on the TV, controller
    /// in hand, no menu open.
    private var autoDimAllowed = false

    init(brightness: PScreenBrightness, preference: PExternalDisplayPreference) {
        self.brightness = brightness
        self.preference = preference
    }

    // MARK: - Automatic dimming

    /// Driven by the emulator view as the situation changes. Turning it off also
    /// brings the screen back, so leaving the TV never strands a dark phone.
    func setAutoDimAllowed(_ allowed: Bool) {
        guard allowed != autoDimAllowed else { return }
        autoDimAllowed = allowed
        if allowed {
            armAutoDim()
        } else {
            cancelAutoDim()
            restore()
        }
    }

    /// Any touch counts as "the player is looking at the phone": undim and start
    /// the countdown over, the same bargain as the system's own auto lock.
    func noteActivity() {
        restore()
        armAutoDim()
    }

    private func armAutoDim() {
        cancelAutoDim()
        guard autoDimAllowed else { return }
        autoDimTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDimDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.blank() }
        }
    }

    private func cancelAutoDim() {
        autoDimTimer?.invalidate()
        autoDimTimer = nil
    }

    // MARK: - Brightness

    func blank() {
        guard !isBlanked else { return }
        let current = brightness.level
        // Persisted before the change, not after: brightness is a system wide
        // setting that outlives the app, so a crash from here on must still be
        // recoverable.
        preference.blankedPhoneBrightness = current
        brightness.level = 0
        isBlanked = true
        print("[PhoneScreen] blanked, saved brightness \(String(format: "%.2f", current))")
    }

    func restore() {
        cancelAutoDim()
        guard isBlanked else { return }
        applySavedBrightness()
        isBlanked = false
    }

    /// Called on launch: if a previous run was killed while blanked, the saved
    /// brightness is still on disk and the panel is still dark.
    func recoverIfNeeded() {
        guard preference.blankedPhoneBrightness != nil else { return }
        print("[PhoneScreen] recovering brightness after an unclean exit")
        applySavedBrightness()
    }

    private func applySavedBrightness() {
        guard let saved = preference.blankedPhoneBrightness else { return }
        // A saved value of 0 would mean restoring to black, which can only be a
        // bad read. Fall back to something clearly usable.
        brightness.level = saved > 0.05 ? saved : 0.5
        preference.blankedPhoneBrightness = nil
    }
}
