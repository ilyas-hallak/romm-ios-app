import Foundation

/// Downloads whatever a remote URL points at and classifies it as either a
/// `.deltaskin` archive or a web page listing skins to pick from.
///
/// A desktop Safari User-Agent is sent because several skin sites (e.g.
/// deltastyles.com) return 403 to non-browser requests.
final class ControllerSkinDownloadService: PControllerSkinDownloader {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(from url: URL) async throws -> ControllerSkinDownload {
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

        // ZIP magic bytes: a `.deltaskin` is a ZIP archive.
        if data.prefix(2).elementsEqual([0x50, 0x4B]) {
            let fileName = url.lastPathComponent.isEmpty ? "skin.deltaskin" : url.lastPathComponent
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: tempURL)
            try data.write(to: tempURL)
            return .skin(fileURL: tempURL)
        }

        // Detect HTML by Content-Type header or by the document's leading bytes.
        let contentType = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type") ?? ""
        let looksLikeHTML = contentType.lowercased().contains("text/html")
            || isHTMLPrefix(data)

        if looksLikeHTML {
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? ""
            return .webPage(html: html)
        }

        throw ControllerSkinError.notASkinFile
    }

    // MARK: - Private

    private func isHTMLPrefix(_ data: Data) -> Bool {
        // Check the first 512 bytes; real HTML almost always starts within that range.
        let prefix = data.prefix(512)
        guard let text = String(data: prefix, encoding: .utf8)
            ?? String(data: prefix, encoding: .isoLatin1) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html")
    }
}
