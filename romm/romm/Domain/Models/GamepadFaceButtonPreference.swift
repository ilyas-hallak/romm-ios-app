import Foundation

/// Whether the two pairs of face buttons are swapped before they reach a core.
///
/// GameController reports face buttons by position, never by the label printed
/// on the pad, so a Nintendo-style controller (B at the bottom, A on the right)
/// arrives mirrored against what the player reads on the hardware. Flipping A/B
/// and X/Y puts the labels back in place.
///
/// One switch instead of a free remapper, same reasoning as
/// `EmulatorMenuShortcut`: it covers the layout players actually run into
/// without turning input into a configuration surface.
protocol PGamepadFaceButtonPreference: AnyObject {
    /// `false` leaves each engine on the mapping it has always used.
    var isSwapped: Bool { get set }
}
