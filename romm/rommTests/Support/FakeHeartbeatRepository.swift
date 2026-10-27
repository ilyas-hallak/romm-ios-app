//
//  FakeHeartbeatRepository.swift
//  rommTests
//
//  Shared stand-in for `PHeartbeatRepository`, controlling what the cached
//  server version is and what a fresh heartbeat call would answer.
//

import Foundation
@testable import romm

final class FakeHeartbeatRepository: PHeartbeatRepository, @unchecked Sendable {
    let minSupportedServerVersion = "4.1.0"
    let maxSupportedServerVersion = "5.3.0"
    let versionCheckThrottleSeconds: TimeInterval = 30

    var cachedVersion: String?
    var heartbeatResult: Result<Heartbeat, Error> = .success(Heartbeat(version: "4.8.0"))

    func getHeartbeat() async throws -> Heartbeat { try heartbeatResult.get() }
    func getHeartbeat(from serverURL: String) async throws -> Heartbeat { try heartbeatResult.get() }
    func checkServerVersion() async throws -> Heartbeat { try heartbeatResult.get() }
    func checkServerVersion(allowIncompatibleVersion: Bool) async throws -> Heartbeat { try heartbeatResult.get() }
    func getLastKnownServerVersion() -> String? { cachedVersion }
    func getLastVersionCheckTime() -> Date? { nil }
    func saveServerVersion(_ version: String) { cachedVersion = version }
    func clearServerVersion() { cachedVersion = nil }
    func shouldThrottleVersionCheck() -> Bool { false }
    func isVersionCompatible(_ version: String) -> Bool { true }
    func detectAuthCapabilities(serverURL: String) async -> HeartbeatRepository.AuthCapabilities {
        HeartbeatRepository.AuthCapabilities(classic: true, clientTokens: true, cloudflareBlocked: false, unreachable: false)
    }
}

struct FakeHeartbeatError: Error {}
