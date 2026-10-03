import Testing
import Foundation
@testable import romm

struct ExternalPlayDecisionTests {
    private func makeStore() -> UserDefaultsExternalEmulatorHandoffStore {
        UserDefaultsExternalEmulatorHandoffStore(userDefaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    @Test func handsOverARomNeverSeenBefore() {
        let store = makeStore()
        let action = ExternalPlayDecision.action(
            romId: 1, target: .manicEmu, delivery: .pasteboard, handoffStore: store
        )
        #expect(action == .handOver)
    }

    @Test func launchesDirectlyOnceConfirmedHandedOff() {
        let store = makeStore()
        store.markHandedOff(romId: 1, to: .manicEmu)
        let action = ExternalPlayDecision.action(
            romId: 1, target: .manicEmu, delivery: .pasteboard, handoffStore: store
        )
        #expect(action == .launchDirectly)
    }

    /// This was the bug: a pasteboard target such as Manic EMU never gets a
    /// confirmed handoff, since nothing reports back once the user pastes. Before
    /// this decision existed, the second Play tap handed the ROM over again
    /// instead of asking whether it was already imported.
    @Test func asksBeforeRelaunchingAPasteboardTargetCopiedOnceAlready() {
        let store = makeStore()
        store.markCopiedToPasteboard(romId: 1, to: .manicEmu)
        let action = ExternalPlayDecision.action(
            romId: 1, target: .manicEmu, delivery: .pasteboard, handoffStore: store
        )
        #expect(action == .confirmBeforeRelaunching)
    }

    /// The "Open in" menu route reports back on its own, so a pasteboard copy
    /// flag is meaningless there and must never trigger the confirmation.
    @Test func ignoresAPasteboardCopyFlagForAnOpenInMenuTarget() {
        let store = makeStore()
        store.markCopiedToPasteboard(romId: 1, to: .retroarch)
        let action = ExternalPlayDecision.action(
            romId: 1, target: .retroarch, delivery: .openInMenu, handoffStore: store
        )
        #expect(action == .handOver)
    }

    /// A confirmed handoff outranks an older pasteboard-copy flag.
    @Test func launchesDirectlyWhenBothHandedOffAndCopiedToPasteboard() {
        let store = makeStore()
        store.markCopiedToPasteboard(romId: 1, to: .manicEmu)
        store.markHandedOff(romId: 1, to: .manicEmu)
        let action = ExternalPlayDecision.action(
            romId: 1, target: .manicEmu, delivery: .pasteboard, handoffStore: store
        )
        #expect(action == .launchDirectly)
    }
}
