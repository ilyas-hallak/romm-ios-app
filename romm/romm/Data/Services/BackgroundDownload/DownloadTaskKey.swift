//
//  DownloadTaskKey.swift
//  romm
//

import Foundation

/// Ties a URLSession task to the job file it transfers.
///
/// The key rides in `URLSessionTask.taskDescription`, the one per task slot that
/// comes back with the task when the background session is recreated after a
/// restart, so it has to survive a lossless round trip through a string. Its
/// `Codable` form is that same string.
nonisolated struct DownloadTaskKey: Codable, Equatable, RawRepresentable {
    /// A UUID string is hex and hyphens only, so it can never contain this
    /// character. That lets the raw value be split at the first separator and
    /// the remainder be taken verbatim, which leaves ROM file names free to
    /// contain the separator, brackets, dots or anything else.
    static let separator: Character = "|"

    let jobId: UUID
    let fileName: String

    init(jobId: UUID, fileName: String) {
        self.jobId = jobId
        self.fileName = fileName
    }

    var rawValue: String {
        "\(jobId.uuidString)\(Self.separator)\(fileName)"
    }

    /// Nil for anything that was not written by `rawValue`: no separator, a
    /// leading part that is not a UUID, or an empty file name. A task whose
    /// description cannot be parsed belongs to nobody and has to be dropped
    /// rather than guessed at.
    init?(rawValue: String) {
        guard let separatorIndex = rawValue.firstIndex(of: Self.separator) else { return nil }
        guard let jobId = UUID(uuidString: String(rawValue[rawValue.startIndex..<separatorIndex])) else {
            return nil
        }
        let fileName = String(rawValue[rawValue.index(after: separatorIndex)...])
        guard !fileName.isEmpty else { return nil }
        self.init(jobId: jobId, fileName: fileName)
    }
}
