//
//  RomUploadRepositoryTests.swift
//  rommTests
//
//  `availability()` branches on the account's scope and the (cached or
//  freshly fetched) server version.
//

import Testing
@testable import romm

struct RomUploadRepositoryTests {
    private func makeRepository(
        token: FakeTokenProvider = FakeTokenProvider(),
        heartbeat: FakeHeartbeatRepository = FakeHeartbeatRepository()
    ) -> RomUploadRepository {
        RomUploadRepository(apiClient: FakeAPIClient(), tokenProvider: token, heartbeat: heartbeat)
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
}
