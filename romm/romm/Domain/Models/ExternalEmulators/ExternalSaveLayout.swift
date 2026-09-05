import Foundation

/// How an external emulator app names and stores the battery saves it writes,
/// so a save the user made over there can be matched to a ROM over here.
///
/// Only battery saves (SRAM). Save states are deliberately out of scope: the
/// three supported apps have nothing in common there. Delta writes
/// `Save States/<sha1>/<uuid>` with no file extension and keeps the slot and
/// name in Core Data, RetroArch writes `<base>.state<n>` in a parallel tree, and
/// Manic keeps states as Realm blobs that are not files at all. Forcing those
/// into one description would describe none of them.
struct ExternalSaveLayout: Sendable, Equatable {

    /// What the save file is named after.
    ///
    /// Every supported app names it after something the handoff already resolved,
    /// which is why no extra bookkeeping is needed to find it again.
    enum Naming: Sendable, Equatable {
        /// `<gameIdentifier>.<ext>`, the identifier the deep link uses. Delta,
        /// which names a save after the ROM's SHA-1.
        case gameIdentifier
        /// `<ROM file name minus its extension>.<ext>`. RetroArch and Manic, both
        /// of which truncate at the last dot, so `Zelda.gba` becomes `Zelda.srm`.
        case romBaseName
    }

    let naming: Naming

    /// Extensions that count as a battery save for this app.
    ///
    /// A whitelist rather than "everything with a matching name", because these
    /// files do not always sit in a folder of their own: Delta keeps `<sha1>.sav`
    /// beside `<sha1>.gba` and `<sha1>.png`, so matching on the name alone would
    /// offer to upload a ROM or a piece of box art as if it were a save.
    let batteryExtensions: Set<String>

    /// Directories to look in first, relative to the folder the user grants
    /// access to, outermost path component first.
    ///
    /// A hint, never a requirement. These paths come from one user's report on
    /// one device (issue #144), described there as not exhaustive, and two of
    /// them contain a component that varies per system or per core. An app is
    /// also free to move its files between releases. Treating them as the only
    /// place to look would turn any of that into a feature that silently finds
    /// nothing, so a search falls back to walking the granted folder.
    ///
    /// They still earn their place: walking straight to the right directory
    /// avoids reading through a RetroArch folder that also holds the user's
    /// entire ROM collection.
    let searchHints: [String]

    /// How deep to walk below a hint, or below the granted folder when no hint
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

    /// Whether a file with this name and extension is a battery save.
    func isBatterySave(fileName: String, matching key: String) -> Bool {
        guard let found = batteryKey(forFileName: fileName) else { return false }
        return found.caseInsensitiveCompare(key) == .orderedSame
    }

    /// What this file claims to be a save for, or nil when it is not a save.
    ///
    /// The counterpart to `isBatterySave` for the direction a scan actually
    /// runs in: a folder is listed once and each name is asked what it belongs
    /// to, rather than every known ROM asking the folder about itself. Going the
    /// other way would mean deriving a key per ROM, and for the apps that name
    /// saves after a content hash that is a hash of every ROM on the device.
    func batteryKey(forFileName fileName: String) -> String? {
        let name = fileName as NSString
        guard batteryExtensions.contains(name.pathExtension.lowercased()) else { return nil }
        return name.deletingPathExtension
    }
}
