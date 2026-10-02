import Foundation

/// A phone on the network that offers itself as the screen to play on.
///
/// `id` is the Bonjour service name, which is what the client hands back to
/// connect. The endpoint behind it stays in the network layer.
struct RemoteControllerHost: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}
