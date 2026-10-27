import Foundation

/// Where the pad stands with the host it wants to play on.
enum RemoteControllerLinkState: Equatable, Sendable {
    case idle
    case searching
    case connecting(hostName: String)
    case connected(hostName: String)
    case failed(message: String)
}
