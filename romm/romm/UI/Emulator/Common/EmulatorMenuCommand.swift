import Foundation

/// What a controller can ask of the in-game menu, independent of the engine
/// that read the buttons.
enum EmulatorMenuCommand: Equatable {
    case up, down, left, right
    case confirm
    case back
}

extension EmulatorMenuCommand {

    /// The quit confirmation is a system alert, which a pad cannot steer, so the
    /// menu answers it: confirm quits, back cancels, anything else waits.
    func answerQuitConfirmation(quit: () -> Void, cancel: () -> Void) {
        switch self {
        case .confirm: quit()
        case .back: cancel()
        default: break
        }
    }
}

/// Turns one analog stick axis into discrete menu steps.
///
/// A step fires once the stick is pushed past `pressThreshold` and the axis has
/// to come back below `releaseThreshold` before the next one, so a stick resting
/// slightly off centre does not scroll the menu on its own.
struct EmulatorMenuStickAxis {
    private let negative: EmulatorMenuCommand
    private let positive: EmulatorMenuCommand
    private var isLatched = false
    private var position: Float = 0

    private static let pressThreshold: Float = 0.5
    private static let releaseThreshold: Float = 0.3

    init(negative: EmulatorMenuCommand, positive: EmulatorMenuCommand) {
        self.negative = negative
        self.positive = positive
    }

    /// - Parameter value: Axis position from -1 to 1.
    /// - Returns: The step to take, if this update completes one.
    mutating func update(_ value: Float) -> EmulatorMenuCommand? {
        position = value
        if abs(value) < Self.releaseThreshold {
            isLatched = false
            return nil
        }
        guard !isLatched, abs(value) >= Self.pressThreshold else { return nil }
        isLatched = true
        return value < 0 ? negative : positive
    }

    /// For sources that report an axis as two halves, like DeltaCore's
    /// `leftThumbstickUp` and `leftThumbstickDown`. A half going to zero only
    /// centres the axis when it was that half that held it, because the other
    /// half may already have taken over in the same update.
    mutating func update(half: Half, magnitude: Float) -> EmulatorMenuCommand? {
        let sign: Float = half == .positive ? 1 : -1
        if magnitude > 0 {
            return update(sign * magnitude)
        }
        guard position * sign > 0 else { return nil }
        return update(0)
    }

    enum Half {
        case negative, positive
    }

    mutating func reset() {
        isLatched = false
        position = 0
    }
}
