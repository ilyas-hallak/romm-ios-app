//
//  HomeViewModelTests.swift
//  rommTests
//
//  `checkUploadSignInHint()` is the one-time "sign in again to upload" hint:
//  it must fire exactly once per installation, and only for `.missingScope`.
//

import Testing
import Foundation
@testable import romm

/// Overrides the one factory method `HomeViewModel` needs beyond what
/// `MockDependencyFactory` already supports via injection (availability),
/// and swaps in an in-memory hint store and a use case double that records
/// whether "sign in again" actually ran, the same way `AccountTestFactory`
/// swaps in its outcome store.
private final class HomeTestFactory: MockDependencyFactory {
    let romUploadRepositoryFake = FakeRomUploadRepository()
    let clearSetupConfigurationUseCaseFake = FakeClearSetupConfigurationUseCase()
    let signInHintStoreFake = InMemoryRomUploadSignInHintStore()

    init(availability: RomUploadAvailability = .available) {
        super.init(apiClient: FakeAPIClient())
        romUploadRepositoryFake.availabilityResult = availability
        romUploadSignInHintStore = signInHintStoreFake
    }

    override func makeGetRomUploadAvailabilityUseCase() -> GetRomUploadAvailabilityUseCase {
        GetRomUploadAvailabilityUseCase(repository: romUploadRepositoryFake)
    }

    override func makeClearSetupConfigurationUseCase() -> PClearSetupConfigurationUseCase {
        clearSetupConfigurationUseCaseFake
    }
}

@MainActor
struct HomeViewModelTests {

    @Test func showsTheHintForMissingScopeWhenNotYetSeen() async {
        let factory = HomeTestFactory(availability: .missingScope)
        let vm = HomeViewModel(factory: factory)

        await vm.checkUploadSignInHint()

        #expect(vm.showUploadSignInAlert)
        // Only showing it marks it as seen, see the "marks after showing" tests below.
        #expect(factory.signInHintStoreFake.hasShownMissingScopeHint == false)
    }

    @Test func doesNotShowTheHintAgainOnceAlreadySeen() async {
        let factory = HomeTestFactory(availability: .missingScope)
        factory.signInHintStoreFake.markMissingScopeHintShown()
        let vm = HomeViewModel(factory: factory)

        await vm.checkUploadSignInHint()

        #expect(vm.showUploadSignInAlert == false)
    }

    @Test func doesNotShowOrMarkTheHintForOtherAvailabilities() async {
        for availability: RomUploadAvailability in [.available, .notAllowedForAccount, .serverTooOld(version: "4.5.0"), .unknown] {
            let factory = HomeTestFactory(availability: availability)
            let vm = HomeViewModel(factory: factory)

            await vm.checkUploadSignInHint()

            #expect(vm.showUploadSignInAlert == false)
            #expect(factory.signInHintStoreFake.hasShownMissingScopeHint == false)
        }
    }

    @Test func checksAvailabilityOnlyOncePerSession() async {
        let factory = HomeTestFactory(availability: .available)
        let vm = HomeViewModel(factory: factory)

        await vm.checkUploadSignInHint()
        await vm.checkUploadSignInHint()

        #expect(factory.romUploadRepositoryFake.availabilityCallCount == 1)
    }

    @Test func signInAgainForUploadMarksTheHintSeenAndRestartsSetup() async {
        let factory = HomeTestFactory(availability: .missingScope)
        let vm = HomeViewModel(factory: factory)
        await vm.checkUploadSignInHint()

        var observedNotification = false
        let observer = NotificationCenter.default.addObserver(forName: .restartSetupRequested, object: nil, queue: nil) { _ in
            observedNotification = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        vm.signInAgainForUpload()

        #expect(factory.signInHintStoreFake.hasShownMissingScopeHint)
        #expect(factory.clearSetupConfigurationUseCaseFake.executeCallCount == 1)
        #expect(observedNotification)
    }

    @Test func dismissingTheHintJustMarksItSeen() async {
        let factory = HomeTestFactory(availability: .missingScope)
        let vm = HomeViewModel(factory: factory)
        await vm.checkUploadSignInHint()

        vm.dismissUploadSignInHint()

        #expect(factory.signInHintStoreFake.hasShownMissingScopeHint)
        #expect(factory.clearSetupConfigurationUseCaseFake.executeCallCount == 0)
    }
}
