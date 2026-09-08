import Foundation

/// Delta stores an imported game under the SHA-1 of its ROM and resolves
/// `delta://game/<sha1>` against that, so the identifier has to be computed from
/// the file's contents rather than its name.
///
/// Delta unpacks archives itself and then hashes what came out, never the
/// archive. Rather than guessing which entry it would pick, the handoff unpacks
/// first and passes the plain ROM, which makes the hash we compute and the one
/// Delta computes the same by construction.
struct DeltaExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .delta }
    var displayName: String { "Delta" }
    var urlScheme: String { "delta" }
    var identifierKind: ExternalGameIdentifierKind { .sha1OfROMData }
    var wantsUnpackedROM: Bool { true }

    /// Delta names a save after the same SHA-1 it addresses the game by, which is
    /// the one certain thing about its storage: that identifier is already
    /// resolved for the deep link, so nothing new has to be worked out.
    ///
    /// Where the file sits is not certain. Issue #144 reports `Delta/Database/`
    /// and notes the naming looks internal; the save has elsewhere been described
    /// as sitting beside the ROM. Both are offered as hints and neither is
    /// required, so a wrong guess costs a folder walk rather than the feature.
    var saveLayout: ExternalSaveLayout? {
        ExternalSaveLayout(
            naming: .gameIdentifier,
            batteryExtensions: ["sav"],
            searchHints: ["Database", "Games"]
        )
    }

    /// Sideloaded builds get a team id appended to the bundle identifier, so this
    /// matches on the prefix rather than the exact App Store one.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix("com.rileytestut.delta")
    }
}
