//
//  Collection.swift
//  romm
//
//  Created by Ilyas Hallak on 10.08.25.
//

import Foundation

struct Collection: Identifiable, Hashable {
    let id: Int
    let name: String
    let description: String
    let romIds: Set<Int>
    let romCount: Int
    let urlCover: String?
    let pathCoversSmall: [String]
    let userId: Int
    let userUsername: String
    let isPublic: Bool
    let isFavorite: Bool
    let isVirtual: Bool
    let isSmart: Bool
    let createdAt: String
    let updatedAt: String
}

struct VirtualCollection: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let romIds: Set<Int>
    let romCount: Int
    let urlCover: String?
    let type: String
    let isPublic: Bool
    let isFavorite: Bool
    let isVirtual: Bool
    let createdAt: String
    let updatedAt: String
}

enum CollectionType: String, CaseIterable {
    case all = "all"
    case favorites = "favorites"
    case recent = "recent"
    case mostPlayed = "most_played"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .all: return "All ROMs"
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .mostPlayed: return "Most Played"
        case .custom: return "Custom Collections"
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "square.grid.3x3"
        case .favorites: return "heart.fill"
        case .recent: return "clock.fill"
        case .mostPlayed: return "chart.bar.fill"
        case .custom: return "folder.fill"
        }
    }
}