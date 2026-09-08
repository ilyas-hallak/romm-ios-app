import Testing
import Foundation
@testable import romm

struct ExternalEmulatorSetupPlanTests {

    /// An app already on the device should not be told to install it.
    @Test func skipsInstallForAnInstalledApp() {
        let plan = ExternalEmulatorSetupPlan(emulator: .delta, isInstalled: true, hasSaveFolder: false)
        #expect(!plan.steps.contains(.install))
        #expect(plan.steps.first == .handoff)
    }

    @Test func startsWithInstallWhenTheAppIsMissing() {
        let plan = ExternalEmulatorSetupPlan(emulator: .delta, isInstalled: false, hasSaveFolder: false)
        #expect(plan.steps.first == .install)
    }

    /// The handoff is the step that stops Manic from looking broken, so it is
    /// never skipped over regardless of what else is already true.
    @Test(arguments: [true, false])
    func alwaysExplainsTheHandoff(isInstalled: Bool) {
        let plan = ExternalEmulatorSetupPlan(
            emulator: .manicEmu, isInstalled: isInstalled, hasSaveFolder: true
        )
        #expect(plan.steps.contains(.handoff))
    }

    /// Asking again for a folder that was already granted would be busywork.
    @Test func skipsTheFolderStepWhenOneIsAlreadyGranted() {
        let plan = ExternalEmulatorSetupPlan(emulator: .retroarch, isInstalled: true, hasSaveFolder: true)
        #expect(!plan.steps.contains(.saveFolder))
    }

    @Test func asksForAFolderWhenNoneIsGranted() {
        let plan = ExternalEmulatorSetupPlan(emulator: .retroarch, isInstalled: true, hasSaveFolder: false)
        #expect(plan.steps.contains(.saveFolder))
    }

    /// The test run comes last: it is the confirmation, so everything else has
    /// to be in place before it can mean anything.
    @Test func endsWithTheTestRun() {
        let plan = ExternalEmulatorSetupPlan(emulator: .delta, isInstalled: false, hasSaveFolder: false)
        #expect(plan.steps.last == .testRun)
    }

    /// Only the steps that ask for something offer a way past them. Reading is
    /// not one: a Skip beside Continue on the handoff step would be a second
    /// button doing the same thing.
    @Test func onlyStepsThatAskForSomethingCanBeSkipped() {
        #expect(!ExternalEmulatorSetupStep.install.isSkippable)
        #expect(!ExternalEmulatorSetupStep.handoff.isSkippable)
        #expect(ExternalEmulatorSetupStep.saveFolder.isSkippable)
        #expect(ExternalEmulatorSetupStep.testRun.isSkippable)
    }

    /// Every supported app describes where its saves are, so all of them reach
    /// the folder step. This fails the day one is added that does not.
    @Test(arguments: ExternalEmulatorID.allCases)
    func everySupportedAppCanBeSetUp(id: ExternalEmulatorID) {
        let plan = ExternalEmulatorSetupPlan(emulator: id, isInstalled: false, hasSaveFolder: false)
        #expect(plan.steps == [.install, .handoff, .saveFolder, .testRun])
    }
}

struct ExternalEmulatorHandoffExplanationTests {

    /// Manic's whole reason for the assistant: it ignores the share sheet, so
    /// without being told the user taps Play and nothing appears to happen.
    @Test func manicSaysToPaste() {
        let text = ManicEmuExternalEmulator().handoffExplanation
        #expect(text.localizedCaseInsensitiveContains("paste"))
        #expect(text.localizedCaseInsensitiveContains("clipboard"))
    }

    /// The apps that do take a document describe the share sheet instead, and
    /// must not tell the user to paste anything.
    @Test(arguments: [ExternalEmulatorID.delta, .retroarch])
    func shareSheetAppsDoNotMentionPasting(id: ExternalEmulatorID) {
        let text = id.emulator.handoffExplanation
        #expect(text.localizedCaseInsensitiveContains("share sheet"))
        #expect(!text.localizedCaseInsensitiveContains("paste"))
    }

    @Test(arguments: ExternalEmulatorID.allCases)
    func everyAppNamesItself(id: ExternalEmulatorID) {
        #expect(id.emulator.handoffExplanation.contains(id.emulator.displayName))
    }
}

struct ExternalEmulatorSetupStoreTests {

    private func makeStore() -> UserDefaultsExternalEmulatorSetupStore {
        let defaults = UserDefaults(suiteName: "setup-tests-\(UUID().uuidString)")!
        return UserDefaultsExternalEmulatorSetupStore(userDefaults: defaults)
    }

    @Test func remembersWhatWasConfigured() {
        let store = makeStore()
        #expect(!store.isConfigured(.delta))
        store.markConfigured(.delta)
        #expect(store.isConfigured(.delta))
        #expect(store.configuredEmulators() == [.delta])
    }

    /// The settings list is built from this, and a list that reorders itself
    /// between launches would move rows under the user's finger.
    @Test func keepsTheOrderTheyWereAddedIn() {
        let store = makeStore()
        store.markConfigured(.manicEmu)
        store.markConfigured(.delta)
        #expect(store.configuredEmulators() == [.manicEmu, .delta])
    }

    @Test func addingTwiceDoesNotDuplicate() {
        let store = makeStore()
        store.markConfigured(.delta)
        store.markConfigured(.delta)
        #expect(store.configuredEmulators() == [.delta])
    }

    @Test func forgettingRemovesIt() {
        let store = makeStore()
        store.markConfigured(.delta)
        store.forget(.delta)
        #expect(store.configuredEmulators().isEmpty)
    }

    /// A build that no longer knows an app must not erase a setup that a build
    /// which does know it would still use.
    @Test func ignoresUnknownStoredValuesWithoutDroppingThem() {
        let defaults = UserDefaults(suiteName: "setup-tests-\(UUID().uuidString)")!
        defaults.set(["delta", "some-future-emulator"], forKey: "externalEmulator.configured")
        let store = UserDefaultsExternalEmulatorSetupStore(userDefaults: defaults)

        #expect(store.configuredEmulators() == [.delta])
        #expect(defaults.stringArray(forKey: "externalEmulator.configured")?.count == 2)
    }
}
