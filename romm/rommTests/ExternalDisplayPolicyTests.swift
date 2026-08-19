import Testing
@testable import romm

struct ExternalDisplayPolicyTests {

    // MARK: - Taking the display over

    @Test func rendersWhenConnectedDuringASessionAndEnabled() {
        #expect(ExternalDisplayPolicy.shouldRenderExternally(
            isDisplayConnected: true, isSessionRunning: true, isPlayOnTVEnabled: true
        ))
    }

    /// Mirroring the library UI is the sensible default for a browsing user.
    @Test func doesNotRenderOutsideASession() {
        #expect(!ExternalDisplayPolicy.shouldRenderExternally(
            isDisplayConnected: true, isSessionRunning: false, isPlayOnTVEnabled: true
        ))
    }

    @Test func doesNotRenderWithoutADisplay() {
        #expect(!ExternalDisplayPolicy.shouldRenderExternally(
            isDisplayConnected: false, isSessionRunning: true, isPlayOnTVEnabled: true
        ))
    }

    /// The opt-out has to win, that is what makes the A/B comparison in the
    /// in-game menu work.
    @Test func doesNotRenderWhenTurnedOff() {
        #expect(!ExternalDisplayPolicy.shouldRenderExternally(
            isDisplayConnected: true, isSessionRunning: true, isPlayOnTVEnabled: false
        ))
    }

    // MARK: - Dimming the phone

    @Test func dimsWhileOnTVWithAController() {
        #expect(ExternalDisplayPolicy.shouldAutoDimPhone(
            isRenderingExternally: true, areTouchControlsHidden: true,
            isMenuOpen: false, isAutoDimPhoneEnabled: true
        ))
    }

    /// Visible touch controls mean the player is holding the phone and playing on
    /// it, so going dark would take the game away.
    @Test func doesNotDimWhileTouchControlsAreVisible() {
        #expect(!ExternalDisplayPolicy.shouldAutoDimPhone(
            isRenderingExternally: true, areTouchControlsHidden: false,
            isMenuOpen: false, isAutoDimPhoneEnabled: true
        ))
    }

    /// The menu is operated by touch.
    @Test func doesNotDimWithTheMenuOpen() {
        #expect(!ExternalDisplayPolicy.shouldAutoDimPhone(
            isRenderingExternally: true, areTouchControlsHidden: true,
            isMenuOpen: true, isAutoDimPhoneEnabled: true
        ))
    }

    /// Mirroring means the phone screen *is* what the TV shows, so blanking it
    /// would blank the TV as well.
    @Test func doesNotDimWhileOnlyMirroring() {
        #expect(!ExternalDisplayPolicy.shouldAutoDimPhone(
            isRenderingExternally: false, areTouchControlsHidden: true,
            isMenuOpen: false, isAutoDimPhoneEnabled: true
        ))
    }

    @Test func doesNotDimWhenTurnedOff() {
        #expect(!ExternalDisplayPolicy.shouldAutoDimPhone(
            isRenderingExternally: true, areTouchControlsHidden: true,
            isMenuOpen: false, isAutoDimPhoneEnabled: false
        ))
    }
}

struct PhoneScreenBlankerTests {

    private final class BrightnessSpy: PScreenBrightness {
        var level: Double = 0.8
    }

    @MainActor
    private func makeBlanker() -> (PhoneScreenBlanker, BrightnessSpy, InMemoryExternalDisplayPreference) {
        let brightness = BrightnessSpy()
        let preference = InMemoryExternalDisplayPreference()
        return (PhoneScreenBlanker(brightness: brightness, preference: preference), brightness, preference)
    }

    @MainActor
    @Test func blankingSavesTheOldBrightnessAndGoesDark() {
        let (blanker, brightness, preference) = makeBlanker()
        blanker.blank()
        #expect(brightness.level == 0)
        #expect(preference.blankedPhoneBrightness == 0.8)
        #expect(blanker.isBlanked)
    }

    @MainActor
    @Test func restoringPutsTheBrightnessBackAndClearsTheRecoveryValue() {
        let (blanker, brightness, preference) = makeBlanker()
        blanker.blank()
        blanker.restore()
        #expect(brightness.level == 0.8)
        #expect(preference.blankedPhoneBrightness == nil)
        #expect(!blanker.isBlanked)
    }

    /// A saved 0 can only be a bad read, and restoring to black would look like a
    /// broken phone.
    @MainActor
    @Test func recoveryRefusesToRestoreToBlack() {
        let brightness = BrightnessSpy()
        brightness.level = 0
        let preference = InMemoryExternalDisplayPreference()
        preference.blankedPhoneBrightness = 0
        let blanker = PhoneScreenBlanker(brightness: brightness, preference: preference)
        blanker.recoverIfNeeded()
        #expect(brightness.level == 0.5)
    }

    @MainActor
    @Test func recoveryDoesNothingAfterACleanExit() {
        let (blanker, brightness, _) = makeBlanker()
        blanker.recoverIfNeeded()
        #expect(brightness.level == 0.8)
    }
}
