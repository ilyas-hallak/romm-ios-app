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
        /// `progress` is 0...1, or nil when the size is unknown. `bytesPerSecond`
        /// is nil until enough time has passed to measure a rate.
        case downloading(progress: Double?, bytesPerSecond: Double? = nil)
        /// Every file is on disk and the ROM is being filed away. Short lived,
        /// but the user must not be able to remove the entry while it runs.
        case finalizing
        case finished
        case failed(String)
        /// The user stopped this download. The entry stays until it is cleared,
        /// so cancelling gives visible feedback rather than a vanishing row.
        case cancelled
    }

    var isActive: Bool {
        switch status {
        case .queued, .downloading, .finalizing: return true
        case .finished, .failed, .cancelled: return false
        }
    }
}

extension DownloadTask {
    /// Rate as e.g. "3,2 MB/s", or nil while none has been measured yet.
    static func formattedRate(_ bytesPerSecond: Double?) -> String? {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
        return "\(bytes)/s"
    }

    /// Line under the bar: percentage and rate, whichever of them is known.
    static func progressLabel(progress: Double?, bytesPerSecond: Double?) -> String {
        let left = progress.map { "\(Int(($0 * 100).rounded()))%" } ?? "Downloading…"
        guard let rate = formattedRate(bytesPerSecond) else { return left }
        return "\(left) · \(rate)"
    }
}
