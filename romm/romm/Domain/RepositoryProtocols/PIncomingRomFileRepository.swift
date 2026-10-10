//
//  PIncomingRomFileRepository.swift
//  romm
//

import Foundation

/// A ROM file handed to the app from outside (Files, Share Sheet, "Open in"),
/// copied into the app's own storage so it survives the source URL going away.
nonisolated struct StagedRomFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    /// Absolute path of the staged copy.
    let fileURL: URL
    /// `<jobId>/<fileName>`, suitable for persisting on a `RomUploadJob` and
    /// resolving back to `fileURL` later via `resolve(relativePath:)`.
    let relativePath: String
}

/// Nonisolated so staging, a copy that can take seconds, runs off the main actor.
nonisolated protocol PIncomingRomFileRepository: Sendable {
    /// Moves `url` into `Application Support/PendingUploads/<jobId>/<fileName>`
    /// when it sits in the app's own Inbox (the copy "Open In" already made
    /// there), or copies it otherwise (e.g. a security-scoped URL from a file
    /// picker, where the source is not ours to move). Security-scoped access
    /// is taken first if the URL needs it. Throws `RomUploadError.emptyFile`
    /// for a zero-byte file, after removing the job folder it created.
    func stage(url: URL) throws -> StagedRomFile

    /// Deletes the staged copy (and its job folder) for a file the user did not
    /// upload after all. `relativePath` is `<jobId>/<fileName>`, as produced by
    /// `stage(url:)`.
    func removeStagedFile(relativePath: String)

    /// Resolves the absolute URL for a job's staged file from the path stored on
    /// a `RomUploadJob`, so a persisted job can be resumed after a relaunch.
    func resolve(relativePath: String) -> URL
}
