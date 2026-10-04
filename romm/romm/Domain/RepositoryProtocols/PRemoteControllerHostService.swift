import Foundation

/// The side that owns the game: it advertises itself on the network and takes
/// button presses from whatever pad joins.
@MainActor
protocol PRemoteControllerHostService: AnyObject {
    /// Called for every button the pad sends.
    var onButton: ((RemoteGamepadButton, Bool) -> Void)? { get set }
    /// Called for every skin input the pad sends, with its name and value.
    var onGameInput: ((String, Double) -> Void)? { get set }
    /// Called when a pad joins or leaves, with its name.
    var onPadChanged: ((String?) -> Void)? { get set }

    func startAdvertising(as hostName: String)
    func stopAdvertising()
    /// Tells the connected pad what to draw. Does nothing without a pad.
    func send(_ layout: RemotePadLayout)
}
