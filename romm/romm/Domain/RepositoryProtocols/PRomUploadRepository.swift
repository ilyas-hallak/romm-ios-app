//
//  PRomUploadRepository.swift
//  romm
//

import Foundation

/// Whether this app instance can upload a ROM to the connected server.
enum RomUploadAvailability: Equatable {
    case available
    /// Signed in, but the account has no `roms.write` scope.
    case missingScope
    /// The chunked upload API is only served from RomM 4.8.0 onwards.
    case serverTooOld(version: String)
    /// No server version could be established yet.
    case unknown
}

/// A typed error for what the upload endpoints can refuse, so callers do not
/// have to pattern match on server text.
enum RomUploadError: LocalizedError {
    case duplicateFileName
    /// The server no longer knows this upload id: the session's TTL expired,
    /// or its cache was flushed. The queue manager restarts the upload once
    /// from scratch rather than surfacing this to the user.
    case sessionExpired
    case other(String)

    var errorDescription: String? {
        switch self {
        case .duplicateFileName:
            return "A file with this name is already on the server."
        case .sessionExpired:
            return "The upload session expired before the file finished uploading."
        case .other(let message):
            return message
        }
    }
}

protocol PRomUploadRepository {
    func availability() async -> RomUploadAvailability

    /// Starts a chunked upload session, returning the server's upload id.
    func start(platformId: Int, fileName: String, fileSize: Int64, totalChunks: Int) async throws -> String

    /// Uploads one chunk, read from `fileURL`, reporting 0...1 progress for that chunk.
    func uploadChunk(uploadId: String, index: Int, fileURL: URL, progress: @escaping (Double) -> Void) async throws

    func complete(uploadId: String) async throws

    /// Idempotent: cancelling a session the server no longer knows about is not an error.
    func cancel(uploadId: String) async throws
}
