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

/// A place inside a granted folder that a save can be written to.
///
/// Carries the emulator rather than only the URL, because the security scope
/// belongs to the granted root and has to be reopened for the write.
struct ExternalSaveDestination: Equatable {
    let emulator: ExternalEmulatorID
    let url: URL
    /// When the file already at this path was last written, nil when the path
    /// is free.
    ///
    /// Carried rather than a plain "exists" flag because a download has to
    /// compare it against what the preview reported: a file written since is
    /// one the plan knows nothing about.
    let existingModifiedAt: Date?

    /// True when a save is already at this path. A write that replaces a file
    /// the emulator app itself put there is the only kind that is certain to be
    /// read back: for anything else the folder and extension are inferred.
    var replacesExistingFile: Bool { existingModifiedAt != nil }
}

/// Reads and writes the folders other emulator apps keep their saves in.
///
/// The bookmark, the security scope and the folder walk live here so the use
/// case only matches names. Writing keeps a copy of whatever it replaced,
/// because a save overwritten in another app's folder cannot be recovered from
/// that app.
protocol PExternalSaveFileRepository {
    /// Every app that currently has a usable grant.
    func emulatorsWithFolder() -> [ExternalEmulatorID]
    /// Nil when no folder was granted, or the app has no described layout.
    func contents(for emulator: ExternalEmulatorID) -> ExternalSaveFolderContents?

    /// The contents of saves the scan found, keyed by URL and skipping any that
    /// no longer read.
    ///
    /// Takes a list rather than one URL because the security scope belongs to
    /// the granted root: reading a batch claims it once instead of per file.
    /// The URLs from a scan cannot be read directly, they are only valid inside
    /// that claim.
    func readSaves(at urls: [URL], for emulator: ExternalEmulatorID) -> [URL: Data]

    /// Where a save named after `baseName` belongs in this app's folder.
    ///
    /// Modelled on a save already sitting there, taking its directory and
    /// extension: an app's layout names several plausible extensions and a
    /// search hint that may not be the folder actually in use, so a neighbour
    /// is the only reliable guide. Nil when the folder holds no save to model
    /// on, rather than guessing a path in someone else's folder.
    func destination(for emulator: ExternalEmulatorID, baseName: String) -> ExternalSaveDestination?

    /// Writes a save into a granted folder, backing up what it replaces and
    /// stamping the file with the server's modification date so the next scan
    /// reports the save as of that time rather than of the write.
    func write(_ data: Data, to destination: ExternalSaveDestination, modifiedAt: Date) throws
}
