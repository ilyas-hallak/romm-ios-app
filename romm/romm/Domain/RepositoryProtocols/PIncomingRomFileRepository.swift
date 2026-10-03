//
//  PIncomingRomFileRepository.swift
//  romm
//

import Foundation

/// A ROM file handed to the app from outside (Files, Share Sheet, "Open in"),
/// copied into the app's own storage so it survives the source URL going away.
struct StagedRomFile: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    /// Absolute path of the staged copy.
    let fileURL: URL
    /// `<jobId>/<fileName>`, suitable for persisting on a `RomUploadJob` and
    /// resolving back to `fileURL` later via `resolve(relativePath:)`.
    let relativePath: String
}

protocol PIncomingRomFileRepository {
    /// Copies `url` into `Application Support/PendingUploads/<jobId>/<fileName>`,
    /// taking security-scoped access first if the URL needs it.
    func stage(url: URL) throws -> StagedRomFile

    /// Deletes the staged copy (and its job folder) for a file the user did not
    /// upload after all.
    func removeStagedFile(_ file: StagedRomFile)

    /// Resolves the absolute URL for a job's staged file from the path stored on
    /// a `RomUploadJob`, so a persisted job can be resumed after a relaunch.
    func resolve(relativePath: String) -> URL
}
