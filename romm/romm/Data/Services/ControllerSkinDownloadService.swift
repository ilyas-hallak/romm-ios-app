import Foundation

/// Downloads a `.deltaskin` file from a remote URL into a temporary file the
/// caller owns.
///
/// A desktop Safari User-Agent is sent because several skin sites (e.g.
/// deltastyles.com) return 403 to non-browser requests.
final class ControllerSkinDownloadService: PControllerSkinDownloader {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(from url: URL) async throws -> URL {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw ControllerSkinError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ControllerSkinError.downloadFailed(statusCode: http.statusCode)
        }

        // A `.deltaskin` is a ZIP archive. Rejecting non-ZIP payloads here turns
        // the common mistake of pasting a link to a skin's web page into a clear
        // error instead of a confusing parse failure later on.
        guard data.prefix(2).elementsEqual([0x50, 0x4B]) else {
            throw ControllerSkinError.notASkinFile
        }

        let fileName = url.lastPathComponent.isEmpty ? "skin.deltaskin" : url.lastPathComponent
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        // Overwrite any leftover file from a previous failed attempt.
        try? FileManager.default.removeItem(at: tempURL)
        try data.write(to: tempURL)

        return tempURL
    }
}
