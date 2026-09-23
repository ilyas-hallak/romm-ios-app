#if !APP_STORE
import DeltaCore

extension RemoteGamepadButton {
    /// The standard controller input this pad button stands for.
    var standardInput: StandardGameControllerInput {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .a: return .a
        case .b: return .b
        case .x: return .x
        case .y: return .y
        case .l1: return .l1
        case .r1: return .r1
        case .l2: return .l2
        case .r2: return .r2
        case .start: return .start
        case .select: return .select
        }
    }
}

/// A phone on the network, presented to DeltaCore as an ordinary controller.
///
/// It reports the `standard` input type and brings no mapping of its own, so
/// every input passes straight through to the core, which resolves it against
/// the running system exactly as it does for the on-screen skin.
final class RemoteGameController: NSObject, GameController {

    let name: String
    var playerIndex: Int?
    let inputType: GameControllerInputType = .standard
    let defaultInputMapping: GameControllerInputMappingProtocol? = nil

    /// Buttons currently held, so the same press is not sent twice and a pad
    /// that leaves can be emptied.
    private var heldButtons: Set<RemoteGamepadButton> = []

    init(name: String, playerIndex: Int) {
        self.name = name
        self.playerIndex = playerIndex
        super.init()
    }

    func set(_ button: RemoteGamepadButton, pressed: Bool) {
        if pressed {
            guard heldButtons.insert(button).inserted else { return }
            activate(button.standardInput)
        } else {
            guard heldButtons.remove(button) != nil else { return }
            deactivate(button.standardInput)
        }
    }

    /// Lifts everything still held, for a pad that goes away mid press.
    func releaseAll() {
        for button in heldButtons {
            deactivate(button.standardInput)
        }
        heldButtons.removeAll()
    }
}
#endif
