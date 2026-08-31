//
//  RefreshRetroAchievementsUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 31.08.26.
//

import Foundation

class RefreshRetroAchievementsUseCase {
    private let authRepository: PAuthRepository

    init(authRepository: PAuthRepository) {
        self.authRepository = authRepository
    }

    /// Returns the user as the server sees them after the refresh, so the caller
    /// can push the new progression into `AppData` in one step.
    func execute(userId: Int, incremental: Bool = true) async throws -> User? {
        try await authRepository.refreshRetroAchievements(userId: userId, incremental: incremental)
    }
}
