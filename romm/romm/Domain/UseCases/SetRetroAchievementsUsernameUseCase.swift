//
//  SetRetroAchievementsUsernameUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 31.08.26.
//

import Foundation

class SetRetroAchievementsUsernameUseCase {
    private let authRepository: PAuthRepository

    init(authRepository: PAuthRepository) {
        self.authRepository = authRepository
    }

    /// The server rejects a blank name silently, so an empty value never leaves
    /// the app. Unlinking is not offered because the API has no way to do it.
    func execute(userId: Int, username: String) async throws -> User? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RetroAchievementsError.emptyUsername }
        return try await authRepository.setRetroAchievementsUsername(userId: userId, username: trimmed)
    }
}

enum RetroAchievementsError: LocalizedError {
    case emptyUsername

    var errorDescription: String? {
        switch self {
        case .emptyUsername:
            return String(localized: "Enter your RetroAchievements username.")
        }
    }
}
