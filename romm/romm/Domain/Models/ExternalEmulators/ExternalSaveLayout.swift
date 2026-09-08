import Foundation

/// How an external emulator app names and stores the battery saves it writes,
/// so a save the user made over there can be matched to a ROM over here.
///
/// Battery saves only. Save states are out of scope because the supported apps
/// have nothing in common there: Delta writes extensionless files under a UUID
/// and keeps the slot in Core Data, RetroArch writes `<base>.state<n>`, and
/// Manic keeps states as Realm blobs that are not files at all.
struct ExternalSaveLayout: Sendable, Equatable {

    /// What the save file is named after, in every case something the handoff
    /// has already resolved.
    enum Naming: Sendable, Equatable {
        /// `<gameIdentifier>.<ext>`. Delta, which names a save after the ROM's
        /// SHA-1.
        case gameIdentifier
        /// `<ROM file name minus its extension>.<ext>`. RetroArch and Manic,
        /// both truncating at the last dot, so `Zelda.gba` becomes `Zelda.srm`.
        case romBaseName
    }

    let naming: Naming

    /// Extensions that count as a battery save for this app.
    ///
    /// A whitelist, because these files do not always sit in a folder of their
    /// own: Delta keeps `<sha1>.sav` beside `<sha1>.gba` and `<sha1>.png`, so
    /// matching on the name alone would offer to upload a ROM as if it were a
    /// save.
    let batteryExtensions: Set<String>

    /// Directories to look in first, relative to the granted folder, outermost
    /// component first.
    ///
    /// A hint, never a requirement: the paths come from one device (issue #144),
    /// some contain a per-system component, and an app may move its files
    /// between releases. A search falls back to walking the granted folder, but
    /// the hints still earn their place by avoiding a read through a RetroArch
    /// folder that also holds the user's whole ROM collection.
    let searchHints: [String]

    /// How deep to walk below a hint, or below the granted folder when none
    /// matched. Enough to absorb one unexpected level of nesting without
    /// descending into a whole library.
    let maxSearchDepth: Int

    init(
        naming: Naming,
        batteryExtensions: Set<String>,
        searchHints: [String] = [],
        maxSearchDepth: Int = 3
    ) {
        self.naming = naming
        self.batteryExtensions = batteryExtensions
        self.searchHints = searchHints
        self.maxSearchDepth = maxSearchDepth
    }

    /// What this file claims to be a save for, or nil when it is not a save.
    ///
    /// Asked per file rather than per ROM, which is the direction a scan runs
    /// in: going the other way would mean deriving a key for every ROM on the
    /// device, and for Delta that key is a content hash.
    func batteryKey(forFileName fileName: String) -> String? {
        let name = fileName as NSString
        guard batteryExtensions.contains(name.pathExtension.lowercased()) else { return nil }
        return name.deletingPathExtension
    }
}
