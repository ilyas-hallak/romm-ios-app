import Foundation

/// Manic EMU keys an imported game on a shortened content hash and resolves
/// `manicemu://game/<id>` against it.
///
/// It reads an unreserved host as a game id in the last path component, so the
/// shared `<scheme>://game/<id>` form works unchanged. Like Delta it unpacks
/// archives and hashes what came out, so the handoff passes the plain ROM.
struct ManicEmuExternalEmulator: PExternalEmulator {
    var id: ExternalEmulatorID { .manicEmu }
    var displayName: String { "Manic EMU" }
    var urlScheme: String { "manicemu" }
    var appStoreURL: URL? { URL(string: "https://apps.apple.com/app/id6743335790") }
    var identifierKind: ExternalGameIdentifierKind { .manicGameID }
    var wantsUnpackedROM: Bool { true }

    /// Manic calls `startAccessingSecurityScopedResource()` on whatever it is
    /// handed and drops the file when that fails, which it always does for the
    /// copy the "Open in" menu leaves in its inbox. Its paste importer reads an
    /// `NSItemProvider` and takes no scope, so the ROM goes over the pasteboard.
    var romDelivery: ExternalROMDelivery { .pasteboard }

    /// Saves land under `3DS/sdmc/saves/<system or core>/`, so the hint stops at
    /// `saves`: the level below it is not one value. `srm` alongside `sav` for
    /// the same reason, since the n64 core writes the libretro extension.
    var saveLayout: ExternalSaveLayout? {
        ExternalSaveLayout(
            naming: .romBaseName,
            batteryExtensions: ["sav", "srm"],
            searchHints: ["3DS/sdmc/saves"]
        )
    }

    /// Systems Manic plays that the built-in engines have no game type for.
    ///
    /// No archives, which Manic unpacks itself, and no disc formats (`cue`,
    /// `iso`, `chd`, `bin`) even though it plays them: those ROMs are a sheet
    /// plus separate tracks, and one hashed file cannot stand in for the set.
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

    /// Sideloaded builds re-sign with a different team, so match the prefix.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix("com.aoshuang.manicemu")
    }
}
