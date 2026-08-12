import Foundation

/// How the emulator video output is positioned within the display ("Controller
/// Mode"). Physical gamepad cases (e.g. GameSir Pocket Taco, GameBaby flip-pad)
/// cover the lower part of the screen, so players want to slide the game up and
/// shrink it. The chosen vertical offset + height apply to both the native
/// (DeltaCore) and libretro renderers in portrait.
enum ControllerScreenMode: String, CaseIterable, Identifiable {
    /// Default rendering — game fills / centers as usual. Custom placement off.
    case off = "off"
    /// Apply the custom placement only while a physical controller is connected.
    case auto = "auto"
    /// Always apply the custom placement, with or without a controller.
    case always = "always"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:    return "Off"
        case .auto:   return "Auto"
        case .always: return "On"
        }
    }
}
