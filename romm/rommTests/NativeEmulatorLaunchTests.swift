#if !APP_STORE
import Foundation
import Testing
import DeltaCore
import GBCDeltaCore
@testable import romm

@MainActor
struct NativeEmulatorLaunchTests {
    @Test func aRejectedStartReportsAnErrorAndCannotRetryThroughResume() async throws {
        Delta.register(GBC.core)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeEmulatorLaunchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gameURL = directory.appendingPathComponent("fixture.gb")
        try Data([0]).write(to: gameURL)
        let factory = MockDependencyFactory()
        factory.saveStore = FakeSaveStore()
        var attempts = 0
        var errors = [String]()
        let session = NativeEmulatorSession(
            gameURL: gameURL, gameType: GBC.core.gameType, romId: 1,
            saveStates: factory.makeEmulatorSaveStatesUseCase(),
            screenPositionPreference: InMemoryEmulatorScreenPositionPreference(),
            startEmulation: {
                attempts += 1
                return false
            }
        )
        defer { session.viewController.game = nil }
        session.onError = { errors.append($0) }

        let launch = try #require(session.start())
        await launch.value
        session.setSceneActive(false)
        session.resume()
        session.setSceneActive(true)

        #expect(attempts == 1)
        #expect(errors.count == 1)
        #expect(errors.first?.isEmpty == false)
        #expect(!session.gameViewControllerShouldResumeEmulation(session.viewController))
        #expect(session.viewController.emulatorCore?.state == .stopped)
        #expect(session.start() == nil)
    }
}
#endif
