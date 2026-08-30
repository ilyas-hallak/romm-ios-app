//
//  User.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

struct User: Identifiable, Equatable {
    let id: Int
    let username: String
    let email: String?
    let role: UserRole
    let avatarPath: String?
    let enabled: Bool
    let retroAchievementsUsername: String?
    let retroAchievementsProgression: [RetroAchievementsProgression]
    
    init(
        id: Int,
        username: String,
        email: String? = nil,
        role: UserRole,
        avatarPath: String? = nil,
        enabled: Bool = true,
        retroAchievementsUsername: String? = nil,
        retroAchievementsProgression: [RetroAchievementsProgression] = []
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.role = role
        self.avatarPath = avatarPath
        self.enabled = enabled
        self.retroAchievementsUsername = retroAchievementsUsername
        self.retroAchievementsProgression = retroAchievementsProgression
    }
}

/// A user's server-supplied RetroAchievements progress for one game.
struct RetroAchievementsProgression: Equatable {
    let gameId: Int
    let awardedCount: Int?
    let maximumCount: Int?
    let earnedAchievements: [EarnedRetroAchievement]

    func earnedAchievement(id: String) -> EarnedRetroAchievement? {
        earnedAchievements.first { $0.id == id }
    }
}

/// A RetroAchievements unlock reported by the RomM server.
struct EarnedRetroAchievement: Equatable {
    let id: String
    let earnedAt: String
    let earnedHardcoreAt: String?
}

enum UserRole: String, CaseIterable {
    case admin = "admin"
    case editor = "editor"
    case viewer = "viewer"
    
    var displayName: String {
        switch self {
        case .admin:
            return "Administrator"
        case .editor:
            return "Editor"
        case .viewer:
            return "Viewer"
        }
    }
}
