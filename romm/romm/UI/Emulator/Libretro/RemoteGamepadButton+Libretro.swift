import Foundation

extension RemoteGamepadButton {
    /// The libretro button this pad button drives.
    ///
    /// Straight across, with no face-button swap in between: the labels on the
    /// remote pad are ones we draw ourselves, so they already read the way the
    /// touch controls do.
    var libretroButton: LibretroABI.JoypadButton {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .a: return .a
        case .b: return .b
        case .x: return .x
        case .y: return .y
        case .l1: return .l
        case .r1: return .r
        case .l2: return .l2
        case .r2: return .r2
        case .start: return .start
        case .select: return .select
        }
    }

    /// The other way round, for the touch pad that speaks libretro. `nil` for
    /// the thumbstick clicks, which no on-screen pad has.
    init?(libretroButton: LibretroABI.JoypadButton) {
        guard let match = RemoteGamepadButton.allCases.first(where: { $0.libretroButton == libretroButton }) else {
            return nil
        }
        self = match
    }
}
