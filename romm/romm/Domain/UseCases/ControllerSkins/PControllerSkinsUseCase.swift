import Foundation

protocol PControllerSkinsUseCase {
    func skins() throws -> [ControllerSkinInfo]
    /// Downloads a `.deltaskin` from `remoteURL` and adds it to the store.
    func addSkin(from remoteURL: URL) async throws -> ControllerSkinInfo
    /// Adds a `.deltaskin` the user picked in the Files app.
    func addSkin(fromFileAt localURL: URL) throws -> ControllerSkinInfo
    func delete(_ skin: ControllerSkinInfo) throws
    func selectedSkin(forGameType gameTypeIdentifier: String) -> ControllerSkinInfo?
    /// Passing `nil` falls back to the core's built-in skin.
    func select(_ skin: ControllerSkinInfo?, forGameType gameTypeIdentifier: String)
    /// File URL of the skin to use for `gameTypeIdentifier`, or `nil` for the built-in skin.
    func selectedSkinFileURL(forGameType gameTypeIdentifier: String) -> URL?
}
