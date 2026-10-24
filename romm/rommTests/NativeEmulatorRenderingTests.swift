#if !APP_STORE
import Foundation
import Testing
import DeltaCore
import GBADeltaCore
import GBCDeltaCore
import MelonDSDeltaCore
import N64DeltaCore
@testable import romm

@MainActor
struct NativeEmulatorRenderingTests {
    @Test(arguments: ["gbc", "gba", "ds"])
    func bitmapSessionConfiguresItsVideoManagerBeforeTheGameIsAssigned(coreName: String) throws {
        let cores: [String: any DeltaCoreProtocol] = [
            "gbc": GBC.core,
            "gba": GBA.core,
            "ds": MelonDS.core
        ]
        let registeredCore = try #require(cores[coreName])

        try withSession(core: registeredCore) { session in
            let core = try #require(session.viewController.emulatorCore)
            #expect(core.state == .stopped)
            #if targetEnvironment(simulator)
            #expect(core.videoManager.options[.metal] as? Bool == true)
            #else
            #expect(core.videoManager.options[.metal] == nil)
            #endif
        }
    }

    @Test func n64SessionKeepsItsExistingOpenGLESRenderer() throws {
        try withSession(core: N64.core) { session in
            let core = try #require(session.viewController.emulatorCore)
            #expect(core.state == .stopped)
            #expect(core.videoManager.options[.metal] == nil)
        }
    }

    private func withSession(
        core: any DeltaCoreProtocol,
        verify: (NativeEmulatorSession) throws -> Void
    ) throws {
        Delta.register(core)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeEmulatorRenderingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The fixture is never executed; assigning the game must configure rendering first.
        let gameURL = directory.appendingPathComponent("fixture.rom")
        try Data([0]).write(to: gameURL)
        let factory = MockDependencyFactory()
        factory.saveStore = FakeSaveStore()
        let session = NativeEmulatorSession(
            gameURL: gameURL,
            gameType: core.gameType,
            romId: 1,
            saveStates: factory.makeEmulatorSaveStatesUseCase(),
            screenPositionPreference: InMemoryEmulatorScreenPositionPreference()
        )
        defer { session.viewController.game = nil }

        try verify(session)
    }
}
#endif
