//
//  DeviceAuthServiceTests.swift
//  rommTests
//
//  `defaultScopes` is the one place the app asks the server for roms.write,
//  so it must stay inside what the server actually accepts.
//

import Testing
@testable import romm

struct DeviceAuthServiceTests {
    /// Scopes the RomM server recognizes (its OAuth scope enum).
    private static let serverKnownScopes: Set<String> = [
        "me.read", "roms.read", "platforms.read", "assets.read", "assets.write",
        "devices.read", "devices.write", "firmware.read", "firmware.write",
        "roms.user.read", "roms.user.write", "collections.read", "collections.write",
        "playlists.read", "playlists.write", "users.read", "users.write",
        "tasks.run", "logs.read", "roms.write"
    ]

    @Test func requestsTheUploadScope() {
        #expect(DeviceAuthService.defaultScopes.contains("roms.write"))
    }

    @Test func staysWithinTheServersScopeLimit() {
        #expect((1...22).contains(DeviceAuthService.defaultScopes.count))
    }

    @Test func containsOnlyScopesTheServerKnowsAbout() {
        for scope in DeviceAuthService.defaultScopes {
            #expect(Self.serverKnownScopes.contains(scope), "unknown scope: \(scope)")
        }
    }
}
