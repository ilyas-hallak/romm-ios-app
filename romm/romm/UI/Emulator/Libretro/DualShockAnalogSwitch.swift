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

    /// One retry covers the case where the pad was already in analog mode.
    private static let maxPresses = 2

    private var wantsAnalog = false
    private var presses = 0
    private var gapFrames = 0
    private var holdFrames = 0

    /// True while the combo replaces the player's own buttons.
    var isPressingCombo: Bool { gapFrames == 0 && holdFrames > 0 }

    mutating func requestAnalog() {
        wantsAnalog = true
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
        guard wantsAnalog else { return }
        if analog || presses >= Self.maxPresses {
            wantsAnalog = false
            holdFrames = 0
        } else {
            // The core only sees a new press after a frame with the combo released.
            press(afterGap: 1)
        }
    }

    /// Reads the core's toggle message, nil for any other message.
    static func reportedMode(in message: String) -> Bool? {
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
