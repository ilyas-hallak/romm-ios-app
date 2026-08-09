import Foundation

/// Resolves the filename/extension to use when persisting a downloaded file.
enum DownloadFilename {

    /// The file extension to use for a persisted download.
    /// Prefers the `Content-Disposition` filename (the only reliable source of the real
    /// server filename), then the requested path, then the URLSession temp file — which
    /// normally has no meaningful extension. Returns an empty string when none is found.
    static func fileExtension(
        contentDisposition: String?,
        requestedPath: String,
        tempURL: URL
    ) -> String {
        if let filename = ContentDispositionParser.filename(from: contentDisposition) {
            let ext = (filename as NSString).pathExtension
            if !ext.isEmpty { return ext }
        }

        let requestedExtension = (requestedPath as NSString).pathExtension
        if !requestedExtension.isEmpty { return requestedExtension }

        return tempURL.pathExtension
    }
}
