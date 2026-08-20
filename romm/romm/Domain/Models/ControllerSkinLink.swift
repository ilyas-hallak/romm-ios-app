import Foundation

/// A `.deltaskin` download a catalog page links to.
struct ControllerSkinLink: Identifiable, Hashable {
    /// Label shown to the user, taken from the page or derived from the file name.
    let name: String
    let url: URL

    var id: URL { url }
}
