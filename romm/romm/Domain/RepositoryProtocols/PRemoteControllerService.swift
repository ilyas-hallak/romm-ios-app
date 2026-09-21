import Foundation

/// The side that owns the game: it advertises itself on the network and takes
/// button presses from whatever pad joins.
@MainActor
protocol PRemoteControllerHostService: AnyObject {
    /// Name of the pad currently playing, `nil` while none is connected.
    var connectedPadName: String? { get }
    /// Called for every button the pad sends.
    var onButton: ((RemoteGamepadButton, Bool) -> Void)? { get set }
    /// Called when a pad joins or leaves, with its name.
    var onPadChanged: ((String?) -> Void)? { get set }

    func startAdvertising(as hostName: String)
    func stopAdvertising()
}

/// The side that acts as the pad: it looks for hosts and sends its buttons to
/// the one the player picked.
@MainActor
protocol PRemoteControllerClientService: AnyObject {
    var onHostsChanged: (([RemoteControllerHost]) -> Void)? { get set }
    var onStateChanged: ((RemoteControllerLinkState) -> Void)? { get set }

    func startBrowsing()
    func stopBrowsing()
    func connect(to host: RemoteControllerHost, as padName: String)
    func disconnect()
    func send(_ button: RemoteGamepadButton, pressed: Bool)
}
