import Foundation

/// Keeps the security-scoped bookmarks for the folders the user granted, one
/// per external emulator app.
final class UserDefaultsExternalSaveFolderStore: PExternalSaveFolderStore {

    private let logger = Logger.emulator
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    private func key(for emulator: ExternalEmulatorID) -> String {
        "externalSaveFolder.\(emulator.rawValue)"
    }

    func remember(folderURL: URL, for emulator: ExternalEmulatorID) throws {
        // The picked URL is already scoped; the bookmark has to be taken while
        // that claim is held or it cannot be resolved later.
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }
        // iOS has no security-scope option here: a plain bookmark of a picked
        // URL is already scoped, and passing the macOS-only option throws.
        let data = try folderURL.bookmarkData()
        userDefaults.set(data, forKey: key(for: emulator))
        logger.info("Remembered save folder for \(emulator.rawValue): \(folderURL.lastPathComponent)")
    }

    func grantedFolder(for emulator: ExternalEmulatorID) -> ExternalSaveFolderGrant? {
        guard let data = userDefaults.data(forKey: key(for: emulator)) else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
            if isStale {
                logger.warning("Save folder bookmark for \(emulator.rawValue) is stale")
            }
            return ExternalSaveFolderGrant(url: url, isStale: isStale)
        } catch {
            // A grant that no longer resolves is dropped rather than kept and
            // retried: it stays broken until the user picks the folder again,
            // and keeping it would show the app as connected when it is not.
            logger.warning("Save folder for \(emulator.rawValue) no longer resolves: \(error.localizedDescription)")
            forget(emulator)
            return nil
        }
    }

    func forget(_ emulator: ExternalEmulatorID) {
        userDefaults.removeObject(forKey: key(for: emulator))
    }

    func grantedEmulators() -> [ExternalEmulatorID] {
        ExternalEmulatorID.allCases.filter { userDefaults.data(forKey: key(for: $0)) != nil }
    }
}
