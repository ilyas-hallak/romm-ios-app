import Foundation

/// A single ROM download tracked by the queue.
struct DownloadTask: Identifiable {
    /// The ROM id — also used to de-duplicate (one active download per ROM).
    let id: Int
    let rom: Rom
    let name: String
    let platformSlug: String?
    var status: Status

    enum Status: Equatable {
        case queued
        case downloading(progress: Double?) // 0...1, or nil when size is unknown
        case finished
        case failed(String)
    }

    var isActive: Bool {
        switch status {
        case .queued, .downloading: return true
        case .finished, .failed: return false
        }
    }
}
