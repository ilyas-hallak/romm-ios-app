//
//  RomUploadChunkPlan.swift
//  romm
//

import Foundation

/// Pure chunk math for the upload, kept apart from any networking so it can be
/// tested without a file or a server.
enum RomUploadChunkPlan {
    /// Server max is 64 MiB per chunk; this stays well under it.
    static let defaultChunkSize: Int64 = 10 * 1024 * 1024

    static func totalChunks(fileSize: Int64, chunkSize: Int64 = defaultChunkSize) -> Int {
        guard fileSize > 0 else { return 0 }
        return Int((fileSize + chunkSize - 1) / chunkSize)
    }

    /// Byte range `[start, end)` of a chunk within the whole file.
    static func range(forChunk index: Int, fileSize: Int64, chunkSize: Int64 = defaultChunkSize) -> Range<Int64> {
        let start = Int64(index) * chunkSize
        let end = min(start + chunkSize, fileSize)
        return start..<end
    }
}
