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

    /// What an internal battery save is called on the wire.
    ///
    /// Shared, because negotiation reports it and applying uploads under it:
    /// two spellings would have the server file one device's save twice.
    static let batteryFileName = "battery.sav"

    /// The slot a battery save from another emulator app pairs under.
    ///
    /// One slot per app rather than sharing `battery`, because pairing keys on
    /// the slot alone: two saves in the same slot are read as one save that
    /// changed, so each sync would push whichever was written last over the
    /// other. They are genuinely separate saves, sitting in separate apps, and
    /// stay separate here.
    static func battery(for emulator: ExternalEmulatorID) -> String {
        "battery-\(emulator.rawValue)"
    }
}
