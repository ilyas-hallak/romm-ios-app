import Foundation

protocol PSecondControllerPreference: AnyObject {
    /// Let a phone on the network join as player two. Off by default: it opens
    /// a port on the local network, so it has to be the player's choice.
    var acceptsRemotePad: Bool { get set }
}
