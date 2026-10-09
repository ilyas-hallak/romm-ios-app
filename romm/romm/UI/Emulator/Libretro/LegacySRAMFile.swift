import Foundation

/// Battery saves used to sit at `LibretroSaves/<stem>.srm`, shared by every
/// game with that file name. They now carry the rom id, and this brings an old
/// file over to the new name on first launch.
///
/// The old file only moves when it surely belongs to this game: its bytes
/// match the stored save, or no other downloaded ROM has that file name. It is
/// copied, never moved or deleted. Whether it then beats the stored save is
/// up to `CoreBatteryFile.stage()`, so only a newer file wins.
struct LegacySRAMFile {
    let legacyURL: URL
    let url: URL
    let romId: Int
    let saveStates: PEmulatorSaveStatesUseCase
    let findROMsByFileStem: PFindROMsByFileStemUseCase

    /// Returns whether the old file was copied over.
    @discardableResult
    func migrate() -> Bool {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path),
              let legacy = try? Data(contentsOf: legacyURL),
              belongsToThisROM(legacy) else { return false }
        do {
            try fileManager.copyItem(at: legacyURL, to: url)
            return true
        } catch {
            return false
        }
    }

    private func belongsToThisROM(_ legacy: Data) -> Bool {
        if (try? saveStates.readBattery(romId: romId)) == legacy { return true }
        let stem = legacyURL.deletingPathExtension().lastPathComponent
        guard let owners = try? findROMsByFileStem.execute(stem: stem) else { return false }
        return owners.subtracting([romId]).isEmpty
    }
}
