import Foundation
@testable import romm

/// Controllable `PExternalAppLauncher` double: install/launch/open results are
/// set per test, and every call is recorded for assertions.
final class FakeExternalAppLauncher: PExternalAppLauncher, @unchecked Sendable {
    var installed = true
    var launchResult = true
    var openResult = true
    var openAppStorePageResult = true

    private(set) var launchedGameIdentifiers: [String] = []
    private(set) var openCallCount = 0

    @MainActor func isInstalled(_ emulator: any PExternalEmulator) -> Bool {
        installed
    }

    @MainActor func launch(_ emulator: any PExternalEmulator, gameIdentifier: String) async -> Bool {
        launchedGameIdentifiers.append(gameIdentifier)
        return launchResult
    }

    @MainActor func open(_ emulator: any PExternalEmulator) async -> Bool {
        openCallCount += 1
        return openResult
    }

    @MainActor func openAppStorePage(_ emulator: any PExternalEmulator) async -> Bool {
        openAppStorePageResult
    }
}
