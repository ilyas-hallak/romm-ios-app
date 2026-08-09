import Foundation

protocol PEmulatorScreenPositionPreference: AnyObject {
    var position: EmulatorScreenPosition { get set }

    /// Fraction (0...1) of the available height the video should occupy when
    /// `position == .top`. Ignored for `.center` (which fills as before).
    var heightFraction: Double { get set }
}
