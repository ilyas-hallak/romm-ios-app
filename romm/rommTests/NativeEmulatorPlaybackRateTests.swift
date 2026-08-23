import Testing
@testable import romm

struct NativeEmulatorPlaybackRateTests {
    @Test func normalRateIsOneX() {
        #expect(NativeEmulatorPlaybackRate.value(isFastForwarding: false) == 1.0)
    }

    @Test func fastForwardRateIsTwoX() {
        #expect(NativeEmulatorPlaybackRate.value(isFastForwarding: true) == 2.0)
    }
}
