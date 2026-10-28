#if !APP_STORE
import Testing
@testable import romm

struct NativeEmulatorPlaybackPolicyTests {
    @Test func openingTheCoverKeepsAnOpenMenuPaused() {
        var policy = NativeEmulatorPlaybackPolicy()
        policy.setPaused(true, for: .menu)
        policy.setPaused(true, for: .cover)
        policy.setPaused(false, for: .cover)
        #expect(!policy.shouldRun)
        policy.setPaused(false, for: .menu)
        #expect(policy.shouldRun)
    }

    @Test func dismissingTheMenuDoesNotResumeABackgroundedGame() {
        var policy = NativeEmulatorPlaybackPolicy()
        policy.setPaused(true, for: .menu)
        policy.setPaused(true, for: .inactiveScene)
        policy.setPaused(false, for: .menu)
        #expect(!policy.shouldRun)
        policy.setPaused(false, for: .inactiveScene)
        #expect(policy.shouldRun)
    }

    @Test func finishingAStateRestorePreservesAManualPause() {
        var policy = NativeEmulatorPlaybackPolicy()
        policy.setPaused(true, for: .restoringState)
        policy.setPaused(true, for: .manual)
        policy.setPaused(false, for: .restoringState)
        #expect(!policy.shouldRun)
        policy.setPaused(false, for: .manual)
        #expect(policy.shouldRun)
    }

    @Test func repeatedSceneNotificationsNeedOnlyOneActivation() {
        var policy = NativeEmulatorPlaybackPolicy()
        policy.setPaused(true, for: .inactiveScene)
        policy.setPaused(true, for: .inactiveScene)
        policy.setPaused(false, for: .inactiveScene)
        #expect(policy.shouldRun)
    }
}
#endif
