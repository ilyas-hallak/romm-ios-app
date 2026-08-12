import Foundation

/// User preference for "Controller Mode" screen placement. Shared by the native
/// (DeltaCore) and libretro renderers.
protocol PEmulatorScreenPositionPreference: AnyObject {
    /// When the custom placement takes effect (off / auto-on-controller / always).
    var mode: ControllerScreenMode { get set }

    /// Vertical position of the game inside the free area: `0` = flush top,
    /// `0.5` = centered, `1` = flush bottom. Interpolated for anything between.
    var verticalOffset: Double { get set }

    /// Fraction (0.3...1.0) of the available height the video should occupy.
    /// `1.0` means "fill the height" (subject to aspect ratio).
    var heightFraction: Double { get set }
}
