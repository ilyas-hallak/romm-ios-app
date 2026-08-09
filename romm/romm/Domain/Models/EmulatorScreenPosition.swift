import Foundation

/// Vertical placement of the emulator video output within the display.
/// `.top` is useful for physical gamepad cases (e.g. GameBaby / flip-pad
/// style) where the game surface should sit flush with the top of the screen.
enum EmulatorScreenPosition: String, CaseIterable, Identifiable {
    case center = "center"
    case top = "top"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .center: return "Default"
        case .top:    return "Top"
        }
    }
}
