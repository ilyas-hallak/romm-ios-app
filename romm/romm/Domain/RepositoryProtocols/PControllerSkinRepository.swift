import Foundation

/// The on-disk store of imported controller skins.
protocol PControllerSkinRepository {
    /// Every valid skin in the store, sorted by name. Files that don't parse are skipped.
    func installedSkins() throws -> [ControllerSkinInfo]
    /// Copies `fileURL` into the store under `preferredFileName`, replacing a
    /// skin of the same name. Throws if the file isn't a usable skin.
    func store(fileURL: URL, preferredFileName: String) throws -> ControllerSkinInfo
    func delete(_ skin: ControllerSkinInfo) throws
    func fileURL(for skin: ControllerSkinInfo) -> URL
}
