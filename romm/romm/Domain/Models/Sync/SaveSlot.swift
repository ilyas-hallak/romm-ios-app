import Foundation

/// The slot names this app pairs saves under on the server.
///
/// A slot is what RomM pairs saves by: `(rom_id, slot)`, with the file name and
/// the emulator playing no part in it. That is what lets a save written by one
/// app be picked up by another under a different name. The server takes any
/// string here, defines no convention of its own, and treats a *missing* slot as
/// an archival upload that is never paired with anything.
///
/// Two properties of these values matter more than what they say:
///
/// They must be sent byte for byte as written. The database collation is
/// case-insensitive but negotiation pairs in a dictionary keyed on the raw
/// string, so `"Battery"` against a stored `"battery"` yields an upload *and* a
/// download for the same save. Never route these through a locale-aware case
/// change, and never derive one from a display name.
///
/// And they can never change. A slot name is a migration contract: renaming one
/// makes the server treat the entire existing history as absent, exactly as a
/// null slot is treated today.
enum SaveSlot {
    /// Cartridge battery / SRAM, the save the game itself writes.
    ///
    /// Not `"autosave"`, which RomM's own docs use as their example: that reads
    /// as an automatically taken save state, which is a different asset with a
    /// different lifetime.
    static let battery = "battery"
}
