//
//  RomUploadJob.swift
//  romm
//

import Foundation

struct RomUploadJob: Codable, Identifiable, Equatable {
    enum State: Codable, Equatable {
        case queued
        case uploading(progress: Double)
        case finishing
        case completed
        case failed(String)
        case cancelled

        var isActive: Bool {
            switch self {
            case .queued, .uploading, .finishing: return true
            case .completed, .failed, .cancelled: return false
            }
        }
    }

    let id: UUID
    let fileName: String
    let fileSize: Int64
    let platformId: Int
    let platformName: String
    /// Relative to `Application Support`, resolved via `PIncomingRomFileRepository`.
    let stagedFilePath: String
    var uploadId: String?
    var nextChunkIndex: Int
    let totalChunks: Int
    var state: State
}
