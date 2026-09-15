import Foundation

/// A file found in another app's granted folder, not yet matched to a ROM.
struct ExternalSaveCandidate: Equatable {
    let url: URL
    let fileName: String
    let sizeBytes: Int
    let modifiedAt: Date
}

/// What one app's granted folder holds.
struct ExternalSaveFolderContents: Equatable {
    let candidates: [ExternalSaveCandidate]
    /// True when the grant resolved but the folder has moved since.
    let isStale: Bool
}

/// Reads the folders other emulator apps write their saves into.
///
/// Read-only: the entitlement is `user-selected.read-only`, enough to offer
/// these saves to the server but not to write back. The bookmark, the security
/// scope and the folder walk live here so the use case only matches names.
protocol PExternalSaveFileRepository {
    /// Every app that currently has a usable grant.
    func emulatorsWithFolder() -> [ExternalEmulatorID]
    /// Nil when no folder was granted, or the app has no described layout.
    func contents(for emulator: ExternalEmulatorID) -> ExternalSaveFolderContents?
}
