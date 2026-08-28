import Foundation

/// Where a Play tap sends the user.
///
/// Holds the emulator's identity rather than the emulator itself, so it stays
/// `Hashable` and can be used as a SwiftUI picker tag.
enum PlayTarget: Hashable, Sendable {
    case builtIn
    case external(ExternalEmulatorID)

    var externalEmulatorID: ExternalEmulatorID? {
        if case .external(let id) = self { return id }
        return nil
    }
}
