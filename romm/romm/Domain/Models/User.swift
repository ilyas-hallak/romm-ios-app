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
    let lastLogin: Date?
    let lastActive: Date?
    let createdAt: Date?
    let retroAchievementsUsername: String?
    let retroAchievementsProgression: [RetroAchievementsProgression]

    init(
        id: Int,
        username: String,
        email: String? = nil,
        role: UserRole,
        avatarPath: String? = nil,
        enabled: Bool = true,
        lastLogin: Date? = nil,
        lastActive: Date? = nil,
        createdAt: Date? = nil,
        retroAchievementsUsername: String? = nil,
        retroAchievementsProgression: [RetroAchievementsProgression] = []
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.role = role
        self.avatarPath = avatarPath
        self.enabled = enabled
        self.lastLogin = lastLogin
        self.lastActive = lastActive
        self.createdAt = createdAt
        self.retroAchievementsUsername = retroAchievementsUsername
        self.retroAchievementsProgression = retroAchievementsProgression
    }
}

extension User {
    /// The linked RetroAchievements account, or `nil` when there is none.
    ///
    /// The server column defaults to an empty string rather than NULL, so an
    /// unlinked account arrives as `""` and a plain nil-check would miss it.
    var linkedRetroAchievementsUsername: String? {
        guard let name = retroAchievementsUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    /// Totals across every game the server reports progress for, for the
    /// RetroAchievements settings screen.
    var retroAchievementsSummary: RetroAchievementsSummary {
        RetroAchievementsSummary(progressions: retroAchievementsProgression)
    }
}

/// Aggregated RetroAchievements numbers derived from the per-game progression.
struct RetroAchievementsSummary: Equatable {
    let gameCount: Int
    let earnedCount: Int
    let hardcoreCount: Int

    init(progressions: [RetroAchievementsProgression]) {
        gameCount = progressions.count
        // `awardedCount` is the server's own tally and stays right even when a
        // game's earned list was skipped by the incremental sync.
        earnedCount = progressions.reduce(0) { $0 + ($1.awardedCount ?? $1.earnedAchievements.count) }
        hardcoreCount = progressions.reduce(0) { total, progression in
            total + (progression.awardedHardcoreCount
                ?? progression.earnedAchievements.filter { $0.earnedHardcoreAt != nil }.count)
        }
    }
}

/// A user's server-supplied RetroAchievements progress for one game.
struct RetroAchievementsProgression: Equatable {
    let gameId: Int
    let awardedCount: Int?
    let awardedHardcoreCount: Int?
    let maximumCount: Int?
    let earnedAchievements: [EarnedRetroAchievement]

    /// The unlock for `achievement`, or `nil` when the user has not earned it.
    ///
    /// The server identifies unlocks by badge name, not by RetroAchievements ID,
    /// so matching goes through ``RetroAchievement/badgeId``.
    func earnedAchievement(for achievement: RetroAchievement) -> EarnedRetroAchievement? {
        guard let badgeId = achievement.badgeId, !badgeId.isEmpty else { return nil }
        return earnedAchievements.first { $0.id == badgeId }
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
