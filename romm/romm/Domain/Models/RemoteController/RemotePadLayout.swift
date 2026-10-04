import Foundation

/// What the pad draws, as the host tells it for the game it runs.
///
/// Part of the wire format like `RemoteGamepadButton`: cases are only added,
/// a pad that cannot read a newer one keeps what it shows.
enum RemotePadLayout: Codable, Equatable, Sendable {
    /// The generic pad, for libretro games and while no game runs.
    case standard
    /// The standard Delta skin of the system, named by Delta's game type
    /// identifier, e.g. `com.rileytestut.delta.game.n64`.
    case deltaSkin(gameType: String)
}
