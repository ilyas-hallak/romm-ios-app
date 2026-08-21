import Foundation

/// What a pasted link turned out to be. Skin sites are usually browsed as web
/// pages, so a link is just as likely to be a catalog as an actual archive.
enum ControllerSkinDownload {
    /// A skin archive, written to a temporary file the caller owns.
    case skin(fileURL: URL)
    /// A web page that may list skins to pick from.
    case webPage(html: String)
}

/// Fetches whatever a remote URL points at.
protocol PControllerSkinDownloader {
    func download(from url: URL) async throws -> ControllerSkinDownload
}
