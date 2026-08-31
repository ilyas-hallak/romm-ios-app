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

    /// The unlock timestamp, or `nil` when the server sent something unparseable.
    var earnedAtDate: Date? { Self.parseTimestamp(earnedAt) }

    /// RetroAchievements reports timestamps as `"2013-05-20 17:20:19"` in UTC,
    /// while some payloads come through as ISO 8601. Both are accepted so the UI
    /// never has to fall back to showing a raw string.
    static func parseTimestamp(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isoFormatter.date(from: trimmed) ?? plainFormatter.date(from: trimmed)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let plainFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
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
