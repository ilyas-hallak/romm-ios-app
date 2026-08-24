import Foundation

/// Where the Play button sends a ROM: the built-in emulator or an external app.
protocol PPlayTargetPreference: AnyObject {
    var current: PlayTarget { get set }
}

/// Remembers which ROMs have already been handed to which external emulator.
///
/// Once a target app has imported a ROM it can be booted straight through its
/// URL scheme, so the share sheet only has to appear once per ROM and target.
protocol PExternalEmulatorHandoffStore: AnyObject {
    func hasHandedOff(romId: Int, to target: ExternalEmulatorID) -> Bool
    func markHandedOff(romId: Int, to target: ExternalEmulatorID)
    /// Drops the handoff state for a ROM, e.g. after it was deleted locally.
    func forget(romId: Int)

    /// A previously worked out game identifier.
    ///
    /// Cached because deriving one can mean unpacking an archive and hashing the
    /// ROM, which would otherwise happen on every single Play tap. Keyed by kind
    /// rather than by emulator: the SHA-1 of a ROM is the same no matter who asks.
    func cachedGameIdentifier(romId: Int, kind: ExternalGameIdentifierKind) -> String?
    func cacheGameIdentifier(_ identifier: String, romId: Int, kind: ExternalGameIdentifierKind)
}
