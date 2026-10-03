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

    /// Same as the default pasteboard explanation, plus a word on the platform
    /// picker Manic shows on import.
    var handoffExplanation: String {
        String(localized: "\(displayName) cannot take games from the share sheet, so the first time you play one it goes to the clipboard instead. Open \(displayName) and paste it to add it to your library, picking the right system if it asks for one. After that it opens there straight away.")
    }

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
    /// No archives, which Manic unpacks itself. Multi-file disc formats (`cue`,
    /// `bin`, `m3u`, `gdi`, `iso`) stay out too: those ROMs are a sheet plus
    /// separate tracks, and one hashed file cannot stand in for the set. `chd`
    /// and `pbp` are different, a whole PS1 disc packed into one file, so they
    /// hash exactly like any other single ROM file and are the formats RomM
    /// actually serves PS1 as.
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
            // Sony (single-file disc images only)
            "chd", "pbp",
            // Other
            "wad", "iwad", "pwad", "jar"
        ]
    }

    /// Manic's paste importer names the file it stores after the first filename
    /// extension its own `UTType` declares, not the real one, then offers a
    /// platform picker built from that extension. The system's generic `chd`
    /// type resolves to Manic's PSP type, whose candidate list has no PS1, so
    /// this steers the pasteboard item to a Manic type that does list it.
    ///
    /// `pbp` is also PSP's EBOOT format, so unlike `chd` it needs the platform to
    /// tell a PS1 disc from a PSP game, or a PSP `.pbp` would go out as Manic's
    /// PS1 type and its picker would leave PSP off the list.
    func pasteboardTypeIdentifier(forROMExtension extension: String, platformSlug: String) -> String? {
        switch `extension`.lowercased() {
        case "chd": return "public.aoshuang.game.mcd"
        case "pbp": return Platform.isPSP(slug: platformSlug) ? "public.aoshuang.game.psp" : "public.aoshuang.game.ps1"
        default: return nil
        }
    }

    /// Sideloaded builds re-sign with a different team, so match the prefix.
    func matches(bundleIdentifier: String) -> Bool {
        bundleIdentifier.lowercased().hasPrefix("com.aoshuang.manicemu")
    }
}
