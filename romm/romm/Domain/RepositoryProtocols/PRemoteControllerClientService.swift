import Foundation

/// The side that acts as the pad: it looks for hosts and sends its buttons to
/// the one the player picked.
@MainActor
protocol PRemoteControllerClientService: AnyObject {
    var onHostsChanged: (([RemoteControllerHost]) -> Void)? { get set }
    var onStateChanged: ((RemoteControllerLinkState) -> Void)? { get set }
    /// Called when the host says what to draw for its game.
    var onLayoutChanged: ((RemotePadLayout) -> Void)? { get set }

    func startBrowsing()
    func stopBrowsing()
    func connect(to host: RemoteControllerHost, as padName: String)
    func disconnect()
    func send(_ button: RemoteGamepadButton, pressed: Bool)
    func sendGameInput(_ name: String, value: Double)
}
