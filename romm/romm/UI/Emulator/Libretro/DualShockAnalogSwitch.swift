import Foundation

/// Puts the emulated DualShock into analog mode.
///
/// Like the real pad, PCSX ReARMed starts the DualShock in digital mode, where
/// it reports a plain pad and ignores both sticks. Only games that switch the
/// mode themselves leave it. The core has no option to start in analog mode,
/// so this presses its analog toggle combo for one frame, the same as the
/// ANALOG button on the hardware. The toggle flips the mode, so the core's
/// "ANALOG ON/OFF" message tells whether a second press is needed.
struct DualShockAnalogSwitch {

    /// Must match the `pcsx_rearmed_analog_combo` answer. Exact match only,
    /// the core ignores the combo while any other button is held.
    static let combo: Set<LibretroABI.JoypadButton> = [.l, .r, .r3]
    static let coreOptionValue = "l1+r1+r3"

    /// One retry covers the case where the pad was already in the target mode.
    private static let maxPresses = 2

    private var targetAnalog: Bool?
    private var presses = 0
    private var gapFrames = 0
    private var holdFrames = 0

    /// True while the combo replaces the player's own buttons.
    var isPressingCombo: Bool { gapFrames == 0 && holdFrames > 0 }

    mutating func request(analog: Bool) {
        targetAnalog = analog
        presses = 0
        press(afterGap: 0)
    }

    /// Advances the press by one emulated frame.
    mutating func frameDidRun() {
        if gapFrames > 0 {
            gapFrames -= 1
        } else if holdFrames > 0 {
            holdFrames -= 1
        }
    }

    /// Feeds back the mode the core reported after a toggle.
    mutating func coreReported(analog: Bool) {
        guard let target = targetAnalog else { return }
        if analog == target || presses >= Self.maxPresses {
            targetAnalog = nil
            holdFrames = 0
        } else {
            // The message comes from inside retro_run, so this frame's
            // frameDidRun still follows. A gap of 2 leaves one released frame.
            press(afterGap: 2)
        }
    }

    /// Reads the core's toggle message, nil for any other message.
    static func reportedMode(in message: String) -> Bool? {
        // Exact texts PCSX ReARMed's update_input shows when the combo toggles the mode.
        switch message {
        case "ANALOG ON": return true
        case "ANALOG OFF": return false
        default: return nil
        }
    }

    private mutating func press(afterGap gap: Int) {
        presses += 1
        gapFrames = gap
        holdFrames = 1
    }
}
