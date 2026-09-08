import Foundation

/// The slot names this app pairs saves under on the server.
///
/// RomM pairs saves by `(rom_id, slot)`; file name and emulator play no part,
/// and a save without a slot is filed as archival and never pairs. So the value
/// must be sent byte for byte, since negotiation keys on the raw string, and it
/// can never change, since renaming a slot makes the server treat the existing
/// history as absent.
enum SaveSlot {
    /// Cartridge battery / SRAM, the save the game itself writes. Not
    /// `"autosave"`, which reads as a save state: a different asset.
    static let battery = "battery"
}
