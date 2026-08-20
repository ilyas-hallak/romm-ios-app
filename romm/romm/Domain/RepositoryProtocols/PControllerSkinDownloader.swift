import Foundation

/// Fetches a skin file from a remote URL into a temporary file.
protocol PControllerSkinDownloader {
    /// Downloads `url` and returns a temporary file the caller owns.
    func download(from url: URL) async throws -> URL
}
