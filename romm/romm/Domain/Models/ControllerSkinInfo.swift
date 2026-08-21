import Foundation

/// A `.deltaskin` controller skin stored in the app's skin folder.
///
/// The file name is the identity. Skins can also be dropped into the folder via
/// the Files app, so the list is always derived by scanning the folder, rather
/// than from an index that could drift out of sync with what's on disk.
struct ControllerSkinInfo: Identifiable, Hashable {
    /// File name including the `.deltaskin` extension.
    let fileName: String
    /// Display name from the skin's `info.json`.
    let name: String
    /// Skin identifier from `info.json`, unique per skin author.
    let identifier: String
    /// Delta game type the skin was made for, e.g. `com.rileytestut.delta.game.gba`.
    let gameTypeIdentifier: String

    var id: String { fileName }
}
