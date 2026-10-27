import Foundation

/// The file name this app reports for a battery save when it has no better
/// one to offer.
///
/// Pairing is by `(rom_id, slot)` and never by name (see `SaveSlot`), so this
/// is cosmetic, it only decides what shows up in the web UI. A live emulator
/// session knows the ROM's actual file on disk and names its battery save
/// after it (see `NativeEmulatorViewModel`/`LibretroEmulatorViewModel`); the
/// call sites here only ever know a ROM id, so they share this one fallback
/// instead of each inventing their own.
enum BatterySaveFileName {
    static func fallback(romId: Int) -> String {
        "\(romId).sav"
    }
}
