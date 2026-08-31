//
//  PAuthRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

protocol PAuthRepository {
    var isAuthenticated: Bool { get }
    var currentUser: User? { get }
    
    func login(username: String, password: String) async throws -> User
    func logout() async throws
    func getCurrentUser() async throws -> User?
    /// Has the server pull fresh RetroAchievements progress, then returns the
    /// reloaded user. `incremental` keeps the games whose tallies are unchanged
    /// instead of refetching every single one.
    func refreshRetroAchievements(userId: Int, incremental: Bool) async throws -> User?
    /// Links a RetroAchievements account to the RomM user and returns the
    /// reloaded user. There is no password: the server talks to
    /// RetroAchievements with its own API key, so the name is all it needs.
    func setRetroAchievementsUsername(userId: Int, username: String) async throws -> User?
}