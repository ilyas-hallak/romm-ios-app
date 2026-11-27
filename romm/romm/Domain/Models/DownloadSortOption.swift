import Foundation

enum DownloadSortOption: String, CaseIterable, Identifiable, Codable {
    case downloadDate = "Download Date"
    case alphabetical = "Alphabetical"
    case lastPlayed = "Last Played"

    var id: String { rawValue }

    /// Pure sort with no view or persistence dependency, so it can be tested directly.
    func apply(to roms: [DownloadedROM]) -> [DownloadedROM] {
        switch self {
        case .downloadDate:
            return roms.sorted { $0.downloadedAt > $1.downloadedAt }
        case .alphabetical:
            return roms.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastPlayed:
            return roms.sorted { lhs, rhs in
                switch (lhs.lastPlayedAt, rhs.lastPlayedAt) {
                case let (left?, right?):
                    return left > right
                case (nil, nil):
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                }
            }
        }
    }
}
