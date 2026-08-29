//
//  UserMapper.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

struct UserMapper {
    static func mapFromAPI(_ apiUser: UserSchema) -> User {
        let role = UserRole(rawValue: apiUser.role.rawValue) ?? .viewer
        
        return User(
            id: apiUser.id,
            username: apiUser.username,
            email: apiUser.email,
            role: role,
            avatarPath: apiUser.avatarPath,
            enabled: apiUser.enabled,
            retroAchievementsUsername: apiUser.raUsername,
            retroAchievementsProgression: (apiUser.raProgression?.results ?? []).compactMap { progression in
                guard let gameId = progression.romRaId else { return nil }
                return RetroAchievementsProgression(
                    gameId: gameId,
                    awardedCount: progression.numAwarded,
                    maximumCount: progression.maxPossible,
                    earnedAchievements: progression.earnedAchievements.map {
                        EarnedRetroAchievement(
                            id: $0.id,
                            earnedAt: $0.date,
                            earnedHardcoreAt: $0.dateHardcore
                        )
                    }
                )
            }
        )
    }
}
