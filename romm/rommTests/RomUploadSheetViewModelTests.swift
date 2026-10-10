//
//  RomUploadSheetViewModelTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

/// Overrides the two factory methods `RomUploadSheetViewModel` needs beyond
/// what `MockDependencyFactory` already supports via injection: availability
/// comes from a `FakeRomUploadRepository` this test controls directly, and
/// "sign in again" from a use case double that records its calls.
private final class RomUploadSheetTestFactory: MockDependencyFactory {
    let romUploadRepositoryFake = FakeRomUploadRepository()
    let clearSetupConfigurationUseCaseFake = FakeClearSetupConfigurationUseCase()

    override func makeGetRomUploadAvailabilityUseCase() -> GetRomUploadAvailabilityUseCase {
        GetRomUploadAvailabilityUseCase(repository: romUploadRepositoryFake)
    }

    override func makeClearSetupConfigurationUseCase() -> PClearSetupConfigurationUseCase {
        clearSetupConfigurationUseCaseFake
    }
}

@MainActor
struct RomUploadSheetViewModelTests {
    private func makeFile() -> StagedRomFile {
        StagedRomFile(
            id: UUID(),
            fileName: "game.zip",
            fileSize: 1024,
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("game.zip"),
            relativePath: "job/game.zip"
        )
    }

    private func makeViewModel(availability: RomUploadAvailability) -> (RomUploadSheetViewModel, RomUploadSheetTestFactory) {
        let factory = RomUploadSheetTestFactory(apiClient: FakeAPIClient())
        factory.romUploadRepositoryFake.availabilityResult = availability
        let vm = RomUploadSheetViewModel(file: makeFile(), factory: factory)
        return (vm, factory)
    }

    // MARK: - unavailableMessage

    @Test func unavailableMessageIsNilWhenAvailable() async {
        let (vm, _) = makeViewModel(availability: .available)
        await vm.load()
        #expect(vm.unavailableMessage == nil)
    }

    @Test func unavailableMessageExplainsAMissingScopeAndOffersToSignInAgain() async {
        let (vm, _) = makeViewModel(availability: .missingScope)
        await vm.load()
        #expect(vm.unavailableMessage == "This sign-in does not include permission to upload ROMs. Sign in again and allow uploads to fix it.")
    }

    @Test func unavailableMessageExplainsAnAccountRoleThatCannotUpload() async {
        let (vm, _) = makeViewModel(availability: .notAllowedForAccount)
        await vm.load()
        #expect(vm.unavailableMessage == "Your account is not allowed to upload ROMs. Ask a server admin for a role that can.")
    }

    @Test func unavailableMessageMentionsTheMinimumServerVersion() async {
        let (vm, _) = makeViewModel(availability: .serverTooOld(version: "4.5.0"))
        await vm.load()
        #expect(vm.unavailableMessage == "Uploading needs RomM 4.8.0 or newer. This server is on 4.5.0.")
    }

    @Test func unavailableMessageExplainsAnUnreachableServer() async {
        let (vm, _) = makeViewModel(availability: .unknown)
        await vm.load()
        #expect(vm.unavailableMessage == "Could not reach the server to check whether uploads are supported.")
    }

    // MARK: - canSignInAgain

    @Test func canSignInAgainIsTrueOnlyForMissingScope() async {
        let (missingScope, _) = makeViewModel(availability: .missingScope)
        await missingScope.load()
        #expect(missingScope.canSignInAgain)

        for availability: RomUploadAvailability in [.available, .notAllowedForAccount, .serverTooOld(version: "4.5.0"), .unknown] {
            let (vm, _) = makeViewModel(availability: availability)
            await vm.load()
            #expect(vm.canSignInAgain == false)
        }
    }

    // MARK: - signInAgain()

    @Test func signInAgainClearsSetupAndPostsRestartSetupRequested() async {
        let (vm, factory) = makeViewModel(availability: .missingScope)
        await vm.load()

        var observedNotification = false
        let observer = NotificationCenter.default.addObserver(forName: .restartSetupRequested, object: nil, queue: nil) { _ in
            observedNotification = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        vm.signInAgain()

        #expect(factory.clearSetupConfigurationUseCaseFake.executeCallCount == 1)
        #expect(observedNotification)
    }
}
