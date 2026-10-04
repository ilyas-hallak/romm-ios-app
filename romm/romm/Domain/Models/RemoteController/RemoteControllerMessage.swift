import Foundation

/// What the two phones say to each other.
///
/// A case is only ever added. Each side drops a line it cannot read, so an
/// older phone simply ignores what it does not know.
enum RemoteControllerMessage: Codable, Equatable, Sendable {
    /// First thing the pad sends, so the host can name it in its status.
    case hello(padName: String)
    case button(RemoteGamepadButton, pressed: Bool)
    /// Host to pad: what to draw for the game that runs now.
    case layout(RemotePadLayout)
    /// An input of the skin the pad draws, named as the skin names it, e.g.
    /// `cUp` or `analogStickLeft`. The value runs from 0 to 1, 0 releases it.
    case gameInput(name: String, value: Double)
}
