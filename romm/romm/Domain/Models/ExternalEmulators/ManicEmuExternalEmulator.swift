import Foundation

/// Manic EMU keys an imported game on a shortened content hash and resolves
/// `manicemu://game/<id>` against it.
///
/// It parses an incoming link by looking at the host, and only recognises the
/// handful that belong to the emulators it hands games off to itself; anything
/// else falls through to a lookup of the URL's last path component as a game id.
/// `game` is not one of the reserved hosts, so the shared `<scheme>://game/<id>`
/// form works unchanged.
///
/// Like Delta it unpacks archives and hashes what came out, so the handoff has to
/// pass the plain ROM for our hash and Manic's to agree by construction.
struct ManicEmuExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .manicEmu }
    var displayName: String { "Manic EMU" }
    var urlScheme: String { "manicemu" }
    var identifierKind: ExternalGameIdentifierKind { .manicGameID }
    var wantsUnpackedROM: Bool { true }

    /// Manic calls `startAccessingSecurityScopedResource()` on whatever it is
    /// handed and drops the file when that fails, which it always does for the
    /// copy the "Open in" menu leaves in Manic's own inbox: nothing is imported
    /// and nothing is reported. Its drag and drop and paste importers read an
    /// `NSItemProvider` instead and never take a security scope, so the ROM goes
    /// over the pasteboard.
    var romDelivery: ExternalROMDelivery { .pasteboard }

    /// Systems Manic plays that the built-in engines have no game type for.
    ///
    /// Extensions only, no archives: Manic unpacks those itself and hashes the
    /// result. Also deliberately no disc formats (`cue`, `iso`, `chd`, `bin`, …)
    /// even though Manic plays them, because those ROMs come as a sheet plus
    /// separate tracks and a single hashed file cannot stand in for the set.
    /// Ambiguous `bin` stays out for the same reason: on a PS1 ROM it would match
    /// a data track and hand over something that boots nothing.
    var romExtensions: Set<String>? {
        [
            // Nintendo
            "3ds", "3dsx", "cia", "cci", "cxi",
            "vb", "vboy",
            "min",
            // Sega
            "32x", "sg", "gg", "sms", "bms", "ms",
            // Atari
            "a26", "a52", "a78", "j64", "jag", "lnx",
            // NEC / SNK
            "pce", "sgx", "ngp", "ngpc", "npc",
            // Other
            "wad", "iwad", "pwad", "jar"
        ]
    }

    /// Sideloaded builds (StikStore, SideStore) re-sign with a different team, so
    /// this matches the prefix rather than the exact App Store identifier.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix("com.aoshuang.manicemu")
    }
}
