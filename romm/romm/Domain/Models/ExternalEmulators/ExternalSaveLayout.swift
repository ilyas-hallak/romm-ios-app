import Foundation

/// How an external emulator app names and stores the battery saves it writes,
/// so a save the user made over there can be matched to a ROM over here.
///
/// Battery saves only. The supported apps have nothing in common for save
/// states: Delta keeps the slot in Core Data, RetroArch writes
/// `<base>.state<n>`, and Manic keeps states as Realm blobs, not files.
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

    /// Extensions that count as a battery save for this app. A whitelist,
    /// because these files share a folder with others of the same name: Delta
    /// keeps `<sha1>.sav` beside `<sha1>.gba` and `<sha1>.png`.
    let batteryExtensions: Set<String>

    /// Directories to look in first, relative to the granted folder, outermost
    /// component first.
    ///
    /// A hint, never a requirement: some paths contain a per-system component
    /// and an app may move its files between releases, so a search falls back to
    /// walking the granted folder. The hints avoid reading through a folder that
    /// also holds the user's ROM collection.
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
    /// Asked per file, because a key per ROM would mean hashing the whole
    /// library for the apps that name saves after a content hash.
    func batteryKey(forFileName fileName: String) -> String? {
        let name = fileName as NSString
        guard batteryExtensions.contains(name.pathExtension.lowercased()) else { return nil }
        return name.deletingPathExtension
    }
}
