#if !APP_STORE
import DeltaCore

/// A remote pad that draws the system's Delta skin, presented to DeltaCore as a
/// controller of the skin kind.
///
/// The pad sends the names its skin uses, and those are the running system's
/// own input names. They are resolved here the way DeltaCore resolves its own
/// on-screen skin, so `cUp` on the pad is `cUp` in the core. Names that are not
/// an input of the system, like the skin's menu button, are dropped.
final class RemoteSkinGameController: NSObject, GameController {

    let name: String
    var playerIndex: Int?
    let inputType: GameControllerInputType = .controllerSkin
    let defaultInputMapping: GameControllerInputMappingProtocol?

    private let mapping: RemoteSkinInputMapping
    /// Inputs currently held, so a pad that leaves can be emptied.
    private var heldInputs: Set<String> = []

    init(name: String, playerIndex: Int, gameType: GameType) {
        self.name = name
        self.playerIndex = playerIndex
        self.mapping = RemoteSkinInputMapping(gameType: gameType)
        self.defaultInputMapping = mapping
        super.init()
    }

    /// Sets an input to a value between 0 and 1, where 0 releases it.
    func set(_ inputName: String, value: Double) {
        let input = Self.input(named: inputName)
        guard value.isFinite, mapping.input(forControllerInput: input) != nil else { return }
        if value > 0 {
            heldInputs.insert(inputName)
            activate(input, value: min(value, 1))
        } else {
            guard heldInputs.remove(inputName) != nil else { return }
            deactivate(input)
        }
    }

    /// Lifts everything still held, for a pad that goes away mid press.
    func releaseAll() {
        for inputName in heldInputs {
            deactivate(Self.input(named: inputName))
        }
        heldInputs.removeAll()
    }

    private static func input(named name: String) -> AnyInput {
        AnyInput(stringValue: name, intValue: nil, type: .controller(.controllerSkin))
    }
}

/// Resolves a skin input name against the system's inputs, like DeltaCore's own
/// mapping for `ControllerView` does.
private struct RemoteSkinInputMapping: GameControllerInputMappingProtocol {

    let gameType: GameType

    var gameControllerInputType: GameControllerInputType { .controllerSkin }

    func input(forControllerInput controllerInput: Input) -> Input? {
        guard let core = Delta.core(for: gameType) else { return nil }
        return core.gameInputType.init(stringValue: controllerInput.stringValue)
    }
}
#endif
