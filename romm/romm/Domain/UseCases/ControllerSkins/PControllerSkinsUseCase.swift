import Foundation

/// Outcome of pasting a link into the skin importer.
enum ControllerSkinImport {
    case imported(ControllerSkinInfo)
    /// The link was a catalog page; these are the skins it offers.
    case choices([ControllerSkinLink])
}

protocol PControllerSkinsUseCase {
    func skins() throws -> [ControllerSkinInfo]
    /// Resolves `remoteURL`: a `.deltaskin` is imported straight away, a catalog
    /// page comes back as a list to choose from.
    func importSkin(from remoteURL: URL) async throws -> ControllerSkinImport
    /// Imports one skin the user picked off a catalog page.
    func addSkin(from link: ControllerSkinLink) async throws -> ControllerSkinInfo
    /// Adds a `.deltaskin` the user picked in the Files app.
    func addSkin(fromFileAt localURL: URL) throws -> ControllerSkinInfo
    func delete(_ skin: ControllerSkinInfo) throws
    func selectedSkin(forGameType gameTypeIdentifier: String) -> ControllerSkinInfo?
    /// Passing `nil` falls back to the core's built-in skin.
    func select(_ skin: ControllerSkinInfo?, forGameType gameTypeIdentifier: String)
    /// File URL of the skin to use for `gameTypeIdentifier`, or `nil` for the built-in skin.
    func selectedSkinFileURL(forGameType gameTypeIdentifier: String) -> URL?
}
