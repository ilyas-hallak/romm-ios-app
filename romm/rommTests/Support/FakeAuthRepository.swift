//
//  FakeAuthRepository.swift
//  rommTests
//
//  Shared stand-in for `PAuthRepository`, so tests can script what the
//  current user (and its role scopes) looks like without a real server.
//

import Foundation
@testable import romm

final class FakeAuthRepository: PAuthRepository, @unchecked Sendable {
    var isAuthenticated: Bool = true
    var currentUser: User?
    var getCurrentUserResult: Result<User?, Error> = .success(nil)

    func login(username: String, password: String) async throws -> User {
        guard let user = try getCurrentUserResult.get() else { throw AuthError.unauthorized }
        return user
    }

    func logout() async throws {
        isAuthenticated = false
        currentUser = nil
    }

    func getCurrentUser() async throws -> User? {
        try getCurrentUserResult.get()
    }

    func refreshRetroAchievements(userId: Int, incremental: Bool) async throws -> User? {
        try getCurrentUserResult.get()
    }

    func setRetroAchievementsUsername(userId: Int, username: String) async throws -> User? {
        try getCurrentUserResult.get()
    }
}
