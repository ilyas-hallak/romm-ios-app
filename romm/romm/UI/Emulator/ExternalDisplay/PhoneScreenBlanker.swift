import UIKit
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
/// The brightness is a system-wide setting that survives the app, so the
/// original value is persisted immediately. If the app is killed while blanked,
/// `recoverIfNeeded()` puts it back on the next launch instead of leaving the
/// user with a phone that seems broken.
@MainActor
final class PhoneScreenBlanker: ObservableObject {

    static let shared = PhoneScreenBlanker()

    @Published private(set) var isBlanked = false

    private static let savedBrightnessKey = "phoneScreenBlanker.savedBrightness"

    private init() {}

    func blank() {
        guard !isBlanked else { return }
        let current = UIScreen.main.brightness
        UserDefaults.standard.set(current, forKey: Self.savedBrightnessKey)
        UIScreen.main.brightness = 0
        isBlanked = true
        print("[PhoneScreen] blanked, saved brightness \(String(format: "%.2f", current))")
    }

    func restore() {
        guard isBlanked else { return }
        applySavedBrightness()
        isBlanked = false
    }

    /// Called on launch: if a previous run was killed while blanked, the saved
    /// brightness is still on disk and the panel is still dark.
    static func recoverIfNeeded() {
        guard UserDefaults.standard.object(forKey: savedBrightnessKey) != nil else { return }
        print("[PhoneScreen] recovering brightness after an unclean exit")
        MainActor.assumeIsolated { shared.applySavedBrightness() }
    }

    private func applySavedBrightness() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.savedBrightnessKey) != nil else { return }
        let saved = defaults.double(forKey: Self.savedBrightnessKey)
        // A saved value of 0 would mean restoring to black, which can only be a
        // bad read. Fall back to something clearly usable.
        UIScreen.main.brightness = saved > 0.05 ? CGFloat(saved) : 0.5
        defaults.removeObject(forKey: Self.savedBrightnessKey)
    }
}
