import Foundation

/// A button on the remote pad, as it travels over the network.
///
/// The raw values are part of the wire format. An older phone has to keep
/// talking to a newer one, so they never change, and a case is only ever added.
enum RemoteGamepadButton: String, Codable, CaseIterable, Sendable {
    case up, down, left, right
    case a, b, x, y
    case l1, r1, l2, r2
    case start, select
}
