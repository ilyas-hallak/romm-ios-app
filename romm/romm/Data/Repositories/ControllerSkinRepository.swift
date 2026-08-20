import Foundation

/// Manages the on-disk store of imported controller skins.
///
/// Skins live in `Documents/ControllerSkins`. Because `UIFileSharingEnabled`
/// is set, users can also drop skins there via the Files app, which is exactly
/// why we scan the directory every time instead of keeping a separate index that
/// could drift out of sync.
final class ControllerSkinRepository: PControllerSkinRepository {

    private let inspector: PControllerSkinInspector
    private let fileManager = FileManager.default

    /// Root of the skin store. Injected so tests can point at a temp directory.
    private let baseDirectory: URL

    init(inspector: PControllerSkinInspector, baseDirectory: URL? = nil) {
        self.inspector = inspector
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.baseDirectory = documents.appendingPathComponent("ControllerSkins", isDirectory: true)
        }
    }

    // MARK: - PControllerSkinRepository

    func installedSkins() throws -> [ControllerSkinInfo] {
        try createDirectoryIfNeeded()

        let contents = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let skins = contents
            .filter { $0.pathExtension.lowercased() == "deltaskin" }
            .compactMap { url -> ControllerSkinInfo? in
                // Skip files that don't parse; they may be partially downloaded
                // or belong to a system the app doesn't support.
                try? inspector.inspect(fileURL: url)
            }

        return skins.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func store(fileURL: URL, preferredFileName: String) throws -> ControllerSkinInfo {
        try createDirectoryIfNeeded()

        let sanitized = sanitize(preferredFileName)
        let destination = baseDirectory.appendingPathComponent(sanitized)

        // Validate before touching the store.
        _ = try inspector.inspect(fileURL: fileURL)

        // The store folder is visible in the Files app, so the picked file can
        // already be the destination. Copying it onto itself would delete it.
        if fileURL.standardizedFileURL != destination.standardizedFileURL {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: fileURL, to: destination)
        }

        // Re-inspect from the destination so the returned `fileName` matches
        // what is actually on disk.
        return try inspector.inspect(fileURL: destination)
    }

    func delete(_ skin: ControllerSkinInfo) throws {
        let url = fileURL(for: skin)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func fileURL(for skin: ControllerSkinInfo) -> URL {
        baseDirectory.appendingPathComponent(skin.fileName)
    }

    // MARK: - Private

    private func createDirectoryIfNeeded() throws {
        guard !fileManager.fileExists(atPath: baseDirectory.path) else { return }
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    /// Strips path separators and colon (which maps to `/` on HFS+), keeps
    /// only the last component, and forces the `.deltaskin` extension.
    private func sanitize(_ name: String) -> String {
        let component = (name as NSString).lastPathComponent
        let stripped = component
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        // Strip any existing extension and append the required one.
        let base = (stripped as NSString).deletingPathExtension
        let clean = base.isEmpty ? "skin" : base
        return clean + ".deltaskin"
    }
}
