import Foundation

/// User preference for the emulator screen placement while a physical controller
/// is connected. Shared by the native (DeltaCore) and libretro renderers. The
/// placement only applies in portrait, on single-screen systems, and only while
/// a controller is attached (so a gamepad case doesn't cover the game). The user
/// sets it by dragging the game directly and by the height slider in the menu.
protocol PEmulatorScreenPositionPreference: AnyObject {
    /// Vertical position of the game inside the free area: `0` = flush top,
    /// `0.5` = centered, `1` = flush bottom. Interpolated for anything between.
    var verticalOffset: Double { get set }

    /// Fraction (0.3...1.0) of the available height the video should occupy.
    /// `1.0` means "fill the height" (subject to aspect ratio).
    var heightFraction: Double { get set }
}
