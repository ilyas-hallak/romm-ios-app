import Foundation

/// A battery save found in another app's folder, matched to a ROM here.
struct ExternalSaveFile: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let romId: Int
    let fileName: String
    let sizeBytes: Int
    let modifiedAt: Date

    init(candidate: ExternalSaveCandidate, romId: Int) {
        self.url = candidate.url
        self.romId = romId
        self.fileName = candidate.fileName
        self.sizeBytes = candidate.sizeBytes
        self.modifiedAt = candidate.modifiedAt
    }
}

/// What one app's folder holds.
struct ExternalSaveScan: Equatable {
    let emulator: ExternalEmulatorID
    let matched: [ExternalSaveFile]
    /// Files that look like saves but belong to no ROM this device knows.
    /// Counted rather than dropped: unmatched saves and an empty folder need
    /// opposite fixes.
    let unmatchedFileNames: [String]
    /// True when the granted folder resolved but has moved since.
    let isStale: Bool

    var isEmpty: Bool { matched.isEmpty && unmatchedFileNames.isEmpty }

    /// One line saying what was found, worded so the four outcomes stay apart.
    /// Shared, so settings and sync cannot describe a folder differently.
    var statusSummary: String {
        if isStale {
            return String(localized: "Folder moved, pick it again")
        }
        if isEmpty {
            return String(localized: "No saves found in this folder")
        }
        if matched.isEmpty {
            return String(localized: "\(unmatchedFileNames.count) saves found, none for games you have")
        }
        let found = matched.count == 1
            ? String(localized: "1 save")
            : String(localized: "\(matched.count) saves")
        guard !unmatchedFileNames.isEmpty else { return found }
        return String(localized: "\(found), \(unmatchedFileNames.count) unrecognised")
    }
}
