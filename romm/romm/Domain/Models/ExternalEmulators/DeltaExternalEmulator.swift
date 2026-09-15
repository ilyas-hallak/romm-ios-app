import Foundation

/// Delta stores an imported game under the SHA-1 of its ROM and resolves
/// `delta://game/<sha1>` against that, so the identifier has to be computed from
/// the file's contents rather than its name.
///
/// Delta unpacks archives itself and hashes what came out, never the archive,
/// so the handoff unpacks first and passes the plain ROM rather than guessing
/// which entry Delta would pick.
struct DeltaExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .delta }
    var displayName: String { "Delta" }
    var urlScheme: String { "delta" }
    /// In the EU Delta ships through AltStore, so this page can answer "not
    /// available in your country". Still the only link iOS lets us open.
    var appStoreURL: URL? { URL(string: "https://apps.apple.com/app/id1048524688") }
    var identifierKind: ExternalGameIdentifierKind { .sha1OfROMData }
    var wantsUnpackedROM: Bool { true }

    /// Delta names a save after the same SHA-1 it addresses the game by, which
    /// the deep link has already resolved. Where the file sits is less certain,
    /// so both known locations are hints only and a wrong guess costs a walk.
    var saveLayout: ExternalSaveLayout? {
        ExternalSaveLayout(
            naming: .gameIdentifier,
            batteryExtensions: ["sav"],
            searchHints: ["Database", "Games"]
        )
    }

    /// Sideloaded builds append a team id to the bundle id, so match the prefix.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix("com.rileytestut.delta")
    }
}
