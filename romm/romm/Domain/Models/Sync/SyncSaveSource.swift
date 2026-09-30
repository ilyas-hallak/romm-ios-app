import Foundation

/// Where a battery save being synced lives on this device.
///
/// Carried through negotiation so applying a plan knows which file an operation
/// is about: the server answers per `(rom_id, slot)`, and the slot is the only
/// thing tying a planned operation back to the app that wrote the save.
enum SyncSaveSource: Equatable, Hashable {
    /// This app's own save store, addressed by ROM id alone.
    case internalStore
    /// Another emulator app's folder, at the file the scan found.
    case externalApp(ExternalEmulatorID)

    /// The slot this source pairs under on the server.
    var slot: String {
        switch self {
        case .internalStore: return SaveSlot.battery
        case .externalApp(let emulator): return SaveSlot.battery(for: emulator)
        }
    }

    /// The source a server slot belongs to, or nil for a slot this build does
    /// not own. A newer app version may add slots, and an operation for one of
    /// those must not be applied to the wrong app's folder.
    init?(slot: String?) {
        guard let slot else { return nil }
        if slot == SaveSlot.battery {
            self = .internalStore
            return
        }
        guard let emulator = ExternalEmulatorID.allCases.first(where: {
            SaveSlot.battery(for: $0) == slot
        }) else { return nil }
        self = .externalApp(emulator)
    }

    /// What the sync report calls this source.
    var displayName: String {
        switch self {
        case .internalStore: return String(localized: "This Device")
        case .externalApp(let emulator): return emulator.emulator.displayName
        }
    }
}
