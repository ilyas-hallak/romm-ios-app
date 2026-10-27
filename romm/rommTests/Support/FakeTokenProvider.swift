//
//  FakeTokenProvider.swift
//  rommTests
//
//  Shared stand-in for `PTokenProvider`, so tests never touch the keychain or
//  a real server.
//

import Foundation
@testable import romm

final class FakeTokenProvider: PTokenProvider, @unchecked Sendable {
    var serverURL: String? = "https://example.org"
    var hasScopeResult = true

    func getServerURL() -> String? { serverURL }
    func getKnownServerURLs() -> [String] { serverURL.map { [$0] } ?? [] }
    func getAuthToken() -> String? { "token" }
    func getUsername() -> String? { "tester" }
    func getPassword() -> String? { nil }
    func isConfigured() -> Bool { serverURL != nil }
    func getAuthMethod() -> AuthMethod { .classic }
    func getClientToken() -> String? { nil }
    func getClientTokenInfo() -> ClientTokenInfo? { nil }
    func hasScope(_ scope: String) -> Bool { hasScopeResult }
    var availableScopes: [String]? { nil }
}
