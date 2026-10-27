import Foundation

/// What the two phones say to each other.
enum RemoteControllerMessage: Codable, Equatable, Sendable {
    /// First thing the pad sends, so the host can name it in its status.
    case hello(padName: String)
    case button(RemoteGamepadButton, pressed: Bool)
}
