import Foundation

/// Optional button combination that opens the in-game menu from a physical
/// controller. Deliberately a small fixed set instead of a free remapper: the
/// touch menu button stays available in every case, this is only a convenience
/// for players whose gamepad case covers the screen.
enum EmulatorMenuShortcut: String, CaseIterable, Codable, Sendable {
    case none
    case l3r3
    case l1r1
}

/// User preference for the controller menu shortcut. `none` is the default so
/// no gameplay button combination is claimed unless the user opts in.
protocol PEmulatorMenuShortcutPreference: AnyObject {
    var current: EmulatorMenuShortcut { get set }
}
