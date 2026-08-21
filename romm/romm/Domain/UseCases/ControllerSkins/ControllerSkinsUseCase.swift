import Foundation

final class ControllerSkinsUseCase: PControllerSkinsUseCase {

    private let repository: PControllerSkinRepository
    private let preference: PControllerSkinPreference
    private let downloader: PControllerSkinDownloader
    private let linkParser: PControllerSkinLinkParser

    init(
        repository: PControllerSkinRepository,
        preference: PControllerSkinPreference,
        downloader: PControllerSkinDownloader,
        linkParser: PControllerSkinLinkParser
    ) {
        self.repository = repository
        self.preference = preference
        self.downloader = downloader
        self.linkParser = linkParser
    }

    // MARK: - PControllerSkinsUseCase

    func skins() throws -> [ControllerSkinInfo] {
        try repository.installedSkins()
    }

    func importSkin(from remoteURL: URL) async throws -> ControllerSkinImport {
        switch try await downloader.download(from: remoteURL) {
        case .skin(let tempURL):
            defer { try? FileManager.default.removeItem(at: tempURL) }
            let info = try storeSkin(tempURL: tempURL, sourceURL: remoteURL)
            return .imported(info)
        case .webPage(let html):
            let links = linkParser.links(in: html, pageURL: remoteURL)
            guard !links.isEmpty else { throw ControllerSkinError.noSkinsOnPage }
            return .choices(links)
        }
    }

    func addSkin(from link: ControllerSkinLink) async throws -> ControllerSkinInfo {
        switch try await downloader.download(from: link.url) {
        case .skin(let tempURL):
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return try storeSkin(tempURL: tempURL, sourceURL: link.url)
        case .webPage:
            throw ControllerSkinError.notASkinFile
        }
    }

    func addSkin(fromFileAt localURL: URL) throws -> ControllerSkinInfo {
        // The URL from a document picker is security-scoped; we must bracket
        // the file access explicitly.
        let accessed = localURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { localURL.stopAccessingSecurityScopedResource() }
        }

        return try repository.store(fileURL: localURL, preferredFileName: localURL.lastPathComponent)
    }

    func delete(_ skin: ControllerSkinInfo) throws {
        try repository.delete(skin)
    }

    func selectedSkin(forGameType gameTypeIdentifier: String) -> ControllerSkinInfo? {
        guard let fileName = preference.selectedFileName(forGameType: gameTypeIdentifier) else {
            return nil
        }

        let installed = (try? repository.installedSkins()) ?? []
        if let skin = installed.first(where: { $0.fileName == fileName }) {
            return skin
        }

        // The file was deleted (e.g. by the user via Files app); clean up the
        // stale preference entry so the next call returns nil cleanly.
        preference.setSelectedFileName(nil, forGameType: gameTypeIdentifier)
        return nil
    }

    func select(_ skin: ControllerSkinInfo?, forGameType gameTypeIdentifier: String) {
        preference.setSelectedFileName(skin?.fileName, forGameType: gameTypeIdentifier)
    }

    func selectedSkinFileURL(forGameType gameTypeIdentifier: String) -> URL? {
        guard let skin = selectedSkin(forGameType: gameTypeIdentifier) else { return nil }
        return repository.fileURL(for: skin)
    }

    // MARK: - Private

    /// Saves a downloaded skin temp file into the repository, deriving the file
    /// name from the source URL.
    private func storeSkin(tempURL: URL, sourceURL: URL) throws -> ControllerSkinInfo {
        var preferredName = sourceURL.lastPathComponent
        if (preferredName as NSString).pathExtension.lowercased() != "deltaskin" {
            preferredName += ".deltaskin"
        }
        return try repository.store(fileURL: tempURL, preferredFileName: preferredName)
    }
}
