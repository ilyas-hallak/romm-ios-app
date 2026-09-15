//
//  LibraryScanType.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

/// The scan modes the RomM server accepts. The raw values are the exact strings
/// the server expects in the `scan` event payload.
enum LibraryScanType: String, CaseIterable, Identifiable, Equatable {
    case newPlatforms = "new_platforms"
    case quick
    case update
    case unmatched
    case complete
    case hashes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newPlatforms: return "New Platforms"
        case .quick: return "Quick Scan"
        case .update: return "Metadata Update"
        case .unmatched: return "Unmatched ROMs"
        case .complete: return "Complete Scan"
        case .hashes: return "File Hashes"
        }
    }

    var explanation: String {
        switch self {
        case .newPlatforms:
            return "Only look at platforms that are not in the library yet."
        case .quick:
            return "Pick up new files and skip everything already in the library."
        case .update:
            return "Refresh the metadata of ROMs that already have a match."
        case .unmatched:
            return "Try again on the ROMs that could not be matched to any source."
        case .complete:
            return "Go through every platform and every file, this takes the longest."
        case .hashes:
            return "Recalculate file hashes, used for matching and RetroAchievements."
        }
    }

    var iconName: String {
        switch self {
        case .newPlatforms: return "square.stack.3d.up"
        case .quick: return "bolt"
        case .update: return "arrow.triangle.2.circlepath"
        case .unmatched: return "questionmark.circle"
        case .complete: return "magnifyingglass"
        case .hashes: return "number"
        }
    }
}
