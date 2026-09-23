import Foundation

/// Where the second player's buttons end up while a game runs. Implemented once
/// per engine, so the pad on the other phone knows nothing about either.
@MainActor
protocol PSecondPlayerInput: AnyObject {
    /// A pad joined or left. Leaving has to lift whatever it still held, a pad
    /// that drops off mid press would otherwise stay held down in the core.
    func setSecondPlayerConnected(_ connected: Bool)
    func setSecondPlayerButton(_ button: RemoteGamepadButton, pressed: Bool)
}

extension PSecondPlayerInput {
    /// Player the remote pad drives. The first one belongs to the phone the
    /// game runs on. A second gamepad takes the same player, so the two would
    /// move as one, which is for whoever set both up to sort out.
    static var remotePadPlayer: Int { 1 }
}
