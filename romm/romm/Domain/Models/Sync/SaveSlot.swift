import Foundation

/// The slot names this app pairs saves under on the server.
///
/// RomM pairs saves by `(rom_id, slot)`; file name and emulator play no part,
/// and a missing slot is treated as an archival upload that never pairs. Two
/// constraints follow: the value must be sent byte for byte, because negotiation
/// keys a dictionary on the raw string, so `"Battery"` against a stored
/// `"battery"` yields both an upload and a download for one save. And it can
/// never change, because renaming a slot makes the server treat the whole
/// existing history as absent.
enum SaveSlot {
    /// Cartridge battery / SRAM, the save the game itself writes.
    ///
    /// Not `"autosave"`, RomM's own example, which reads as an automatically
    /// taken save state: a different asset with a different lifetime.
    static let battery = "battery"
}
