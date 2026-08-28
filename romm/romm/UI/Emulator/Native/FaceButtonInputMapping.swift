import DeltaCore

/// Rewrites a DeltaCore input mapping so the two pairs of face buttons drive
/// each other's inputs.
///
/// DeltaCore feeds a core through a controller-specific mapping, so the swap
/// belongs there rather than in the cores: change the mapping once and every
/// system the native engine runs picks it up.
enum FaceButtonInputMapping {

    private static let pairs = [("a", "b"), ("x", "y")]

    /// Returns `mapping` with A/B and X/Y exchanged, or the mapping untouched
    /// when it is not one we can rewrite (a custom mapping type, or nil).
    static func swappingFaceButtons(
        of mapping: GameControllerInputMappingProtocol?
    ) -> GameControllerInputMappingProtocol? {
        guard var mapping = mapping as? GameControllerInputMapping else { return mapping }

        let inputType = mapping.gameControllerInputType
        func controllerInput(_ identifier: String) -> AnyInput {
            AnyInput(stringValue: identifier, intValue: nil, type: .controller(inputType))
        }

        for (first, second) in pairs {
            let firstInput = controllerInput(first)
            let secondInput = controllerInput(second)
            let firstTarget = mapping.input(forControllerInput: firstInput)
            let secondTarget = mapping.input(forControllerInput: secondInput)
            mapping.set(secondTarget, forControllerInput: firstInput)
            mapping.set(firstTarget, forControllerInput: secondInput)
        }

        return mapping
    }
}
