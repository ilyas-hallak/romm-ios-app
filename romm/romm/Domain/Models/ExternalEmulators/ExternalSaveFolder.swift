import Foundation

/// Remembers the folders the user granted access to, one per external emulator
/// app.
///
/// A picked folder is only readable through a security-scoped bookmark, and the
/// grant has to survive relaunches or the user would be re-picking three folders
/// every time they want to sync.
protocol PExternalSaveFolderStore: AnyObject {
    /// Stores the grant for a folder the user just picked.
    func remember(folderURL: URL, for emulator: ExternalEmulatorID) throws
    /// Resolves a previously granted folder, or nil when none was granted or the
    /// grant no longer resolves.
    func grantedFolder(for emulator: ExternalEmulatorID) -> ExternalSaveFolderGrant?
    /// Drops a grant, e.g. when the user picks a different folder or revokes it.
    func forget(_ emulator: ExternalEmulatorID)
    /// Every app that currently has a usable grant.
    func grantedEmulators() -> [ExternalEmulatorID]
}

/// A resolved folder plus the access it needs to actually be read.
///
/// Reading a security-scoped URL has to be bracketed by start/stop calls, and
/// the stop is easy to forget, so the bracket lives here rather than at each
/// call site: the folder can only be reached inside `withAccess`.
struct ExternalSaveFolderGrant {
    let url: URL
    /// False for a bookmark that resolved but whose contents moved, which iOS
    /// reports separately from failure. Worth surfacing, since the usual cause
    /// is the user having moved or renamed the folder.
    let isStale: Bool

    private let scoped: Bool

    init(url: URL, isStale: Bool, scoped: Bool = true) {
        self.url = url
        self.isStale = isStale
        self.scoped = scoped
    }

    /// Runs `body` with the folder accessible, releasing the claim afterwards.
    func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T {
        let accessed = scoped && url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try body(url)
    }
}
