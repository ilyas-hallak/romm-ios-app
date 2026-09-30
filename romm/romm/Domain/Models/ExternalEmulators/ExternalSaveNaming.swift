import Foundation

/// Works out what a save for a given ROM is called inside another app's folder.
///
/// Shared by scanning and syncing, which need the same rule in both directions:
/// scanning maps a file name back to a ROM, syncing has to name the file it
/// writes for one. Two rules would drift apart and a save would land under a
/// name the emulator never reads.
struct ExternalSaveNaming {

    private let handoffStore: PExternalEmulatorHandoffStore

    init(handoffStore: PExternalEmulatorHandoffStore) {
        self.handoffStore = handoffStore
    }

    /// Every name a save for this ROM could carry, without extension.
    ///
    /// More than one for a multi-file ROM under `.romBaseName`: the app named
    /// the save after whichever part it opened, and which one that was is not
    /// recorded here. Empty when the name cannot be told, which for
    /// `.gameIdentifier` means the ROM was never handed over, and a save for a
    /// game that app has never seen cannot exist.
    func baseNames(
        for rom: DownloadedROM,
        emulator: ExternalEmulatorID,
        layout: ExternalSaveLayout
    ) -> [String] {
        switch layout.naming {
        case .romBaseName:
            return rom.files.map { ($0.fileName as NSString).deletingPathExtension }
        case .gameIdentifier:
            let kind = emulator.emulator.identifierKind
            guard let identifier = handoffStore.cachedGameIdentifier(romId: rom.id, kind: kind) else {
                return []
            }
            return [identifier]
        }
    }

    /// The single name to write a save under, or nil when it cannot be told.
    ///
    /// For a multi-file ROM the first part wins: the parts share a base name in
    /// every layout seen so far, and picking one beats writing several files an
    /// app would then disagree about.
    func writeBaseName(
        for rom: DownloadedROM,
        emulator: ExternalEmulatorID,
        layout: ExternalSaveLayout
    ) -> String? {
        baseNames(for: rom, emulator: emulator, layout: layout).first
    }
}
