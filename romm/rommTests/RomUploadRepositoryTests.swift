//
//  RomUploadRepositoryTests.swift
//  rommTests
//
//  `availability()` branches on the account role's scopes, the current
//  sign-in's scope, and the (cached or freshly fetched) server version, in
//  that order.
//

import Testing
@testable import romm

@MainActor
struct RomUploadRepositoryTests {
    private func makeRepository(
        token: FakeTokenProvider = FakeTokenProvider(),
        heartbeat: FakeHeartbeatRepository = FakeHeartbeatRepository(),
        auth: FakeAuthRepository = FakeAuthRepository()
    ) -> RomUploadRepository {
        RomUploadRepository(apiClient: FakeAPIClient(), tokenProvider: token, heartbeat: heartbeat, authRepository: auth)
    }

    private func user(oauthScopes: [String]) -> User {
        User(id: 1, username: "tester", role: .user, oauthScopes: oauthScopes)
    }

    @Test func missingUploadScopeReportsMissingScope() async {
        let token = FakeTokenProvider()
        token.hasScopeResult = false
        let repository = makeRepository(token: token)

        #expect(await repository.availability() == .missingScope)
    }

    @Test func cachedVersionBelowMinimumReportsServerTooOld() async {
        let heartbeat = FakeHeartbeatRepository()
        heartbeat.cachedVersion = "4.7.0"
        let repository = makeRepository(heartbeat: heartbeat)

        #expect(await repository.availability() == .serverTooOld(version: "4.7.0"))
    }

    @Test func cachedVersionAtOrAboveMinimumReportsAvailable() async {
        let heartbeat = FakeHeartbeatRepository()
        heartbeat.cachedVersion = "4.8.0"
        let repository = makeRepository(heartbeat: heartbeat)

        #expect(await repository.availability() == .available)
    }

    @Test func noCachedVersionAndFailingHeartbeatReportsUnknown() async {
        let heartbeat = FakeHeartbeatRepository()
        heartbeat.heartbeatResult = .failure(FakeHeartbeatError())
        let repository = makeRepository(heartbeat: heartbeat)

        #expect(await repository.availability() == .unknown)
    }

    @Test func noCachedVersionFetchesFromHeartbeat() async {
        let heartbeat = FakeHeartbeatRepository()
        heartbeat.heartbeatResult = .success(Heartbeat(version: "5.0.0"))
        let repository = makeRepository(heartbeat: heartbeat)

        #expect(await repository.availability() == .available)
    }

    // MARK: - Role scopes

    @Test func roleWithoutUploadScopeReportsNotAllowedForAccount() async {
        let auth = FakeAuthRepository()
        auth.getCurrentUserResult = .success(user(oauthScopes: ["me.read", "roms.read"]))
        let repository = makeRepository(auth: auth)

        #expect(await repository.availability() == .notAllowedForAccount)
    }

    /// Passwort-Login also has no token scopes of its own, so the role check
    /// is the only thing that can catch a viewer-style account.
    @Test func roleWithoutUploadScopeReportsNotAllowedForAccountEvenWithPasswordLogin() async {
        let token = FakeTokenProvider()
        token.hasScopeResult = true
        let auth = FakeAuthRepository()
        auth.getCurrentUserResult = .success(user(oauthScopes: ["me.read"]))
        let repository = makeRepository(token: token, auth: auth)

        #expect(await repository.availability() == .notAllowedForAccount)
    }

    @Test func roleWithUploadScopeButTokenWithoutItReportsMissingScope() async {
        let token = FakeTokenProvider()
        token.hasScopeResult = false
        let auth = FakeAuthRepository()
        auth.getCurrentUserResult = .success(user(oauthScopes: ["me.read", "roms.write"]))
        let repository = makeRepository(token: token, auth: auth)

        #expect(await repository.availability() == .missingScope)
    }

    @Test func failingToFetchTheUserSkipsTheRoleCheck() async {
        let auth = FakeAuthRepository()
        auth.getCurrentUserResult = .failure(AuthError.networkError)
        let repository = makeRepository(auth: auth)

        #expect(await repository.availability() == .available)
    }

    /// An older server that does not send `oauth_scopes` decodes it as an
    /// empty list; that must not be mistaken for a role with no scopes at all.
    @Test func userWithNoReportedScopesSkipsTheRoleCheck() async {
        let auth = FakeAuthRepository()
        auth.getCurrentUserResult = .success(user(oauthScopes: []))
        let repository = makeRepository(auth: auth)

        #expect(await repository.availability() == .available)
    }
}
