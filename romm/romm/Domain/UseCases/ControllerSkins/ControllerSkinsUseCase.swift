import Foundation

final class ControllerSkinsUseCase: PControllerSkinsUseCase {

    private let repository: PControllerSkinRepository
    private let preference: PControllerSkinPreference
    private let downloader: PControllerSkinDownloader

    init(
        repository: PControllerSkinRepository,
        preference: PControllerSkinPreference,
        downloader: PControllerSkinDownloader
    ) {
        self.repository = repository
        self.preference = preference
        self.downloader = downloader
    }

    // MARK: - PControllerSkinsUseCase

    func skins() throws -> [ControllerSkinInfo] {
        try repository.installedSkins()
    }

    func addSkin(from remoteURL: URL) async throws -> ControllerSkinInfo {
        let tempURL = try await downloader.download(from: remoteURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Prefer the remote URL's filename; the repository will enforce the
        // .deltaskin extension if it's missing.
        var preferredName = remoteURL.lastPathComponent
        if (preferredName as NSString).pathExtension.lowercased() != "deltaskin" {
            preferredName += ".deltaskin"
        }

        return try repository.store(fileURL: tempURL, preferredFileName: preferredName)
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
}
