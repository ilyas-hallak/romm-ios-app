import Foundation

/// One file found in another app's granted folder, before anything is known
/// about which ROM it belongs to.
struct ExternalSaveCandidate: Equatable {
    let url: URL
    let fileName: String
    let sizeBytes: Int
    let modifiedAt: Date
}

/// What one app's granted folder holds right now.
struct ExternalSaveFolderContents: Equatable {
    let candidates: [ExternalSaveCandidate]
    /// True when the grant resolved but the folder has moved since.
    let isStale: Bool
}

/// Reads the folders other emulator apps write their saves into.
///
/// Read-only, and deliberately so: the entitlement is
/// `user-selected.read-only`, which is enough to offer these saves to the server
/// but not to write anything back.
///
/// Owning the bookmark, the security scope and the folder walk here is what
/// keeps them out of `ScanExternalSavesUseCase`, which then only has to match
/// file names to ROMs.
protocol PExternalSaveFileRepository {
    /// Every app that currently has a usable grant.
    func emulatorsWithFolder() -> [ExternalEmulatorID]
    /// Reads one app's granted folder. Returns nil when no folder was granted,
    /// or when the app has no described save layout to look for.
    func contents(for emulator: ExternalEmulatorID) -> ExternalSaveFolderContents?
}
