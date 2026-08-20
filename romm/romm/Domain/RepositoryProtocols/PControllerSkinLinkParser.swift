import Foundation

/// Finds the `.deltaskin` downloads a catalog page offers.
protocol PControllerSkinLinkParser {
    /// Links found in `html`, with relative paths resolved against `pageURL`.
    /// Returns an empty array when the page offers none.
    func links(in html: String, pageURL: URL) -> [ControllerSkinLink]
}
