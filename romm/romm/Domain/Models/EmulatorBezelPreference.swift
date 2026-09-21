import Foundation

/// User preference for the bezel around the web emulator. Off by default, so
/// the edge to edge layout stays what it was until the user asks for a frame.
protocol PEmulatorBezelPreference: AnyObject {
    var isEnabled: Bool { get set }
}
