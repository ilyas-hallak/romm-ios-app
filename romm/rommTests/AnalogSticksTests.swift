import Testing
import Foundation
import CoreGraphics
@testable import romm

@MainActor
struct AnalogStickAxisTests {

    @Test func fullDeflectionMapsToTheLibretroRange() {
        #expect(LibretroFrontend.axisValue(1) == 32767)
        #expect(LibretroFrontend.axisValue(-1) == -32767)
        #expect(LibretroFrontend.axisValue(0) == 0)
    }

    @Test func valuesOutsideTheRangeAreClamped() {
        #expect(LibretroFrontend.axisValue(1.5) == 32767)
        #expect(LibretroFrontend.axisValue(-3) == -32767)
    }
}

@MainActor
struct AnalogStickFrontendStateTests {

    private let frontend = LibretroFrontend.shared

    @Test func eachStickReportsItsOwnAxes() {
        defer { frontend.clearAllButtons(player: 1) }
        frontend.setStick(.left, x: 1, y: -1, player: 1)
        frontend.setStick(.right, x: -0.5, y: 0.5, player: 1)

        #expect(frontend.stickAxis(index: LibretroABI.AnalogStick.left.rawValue, axis: LibretroABI.ANALOG_AXIS_X, player: 1) == 32767)
        #expect(frontend.stickAxis(index: LibretroABI.AnalogStick.left.rawValue, axis: LibretroABI.ANALOG_AXIS_Y, player: 1) == -32767)
        #expect(frontend.stickAxis(index: LibretroABI.AnalogStick.right.rawValue, axis: LibretroABI.ANALOG_AXIS_X, player: 1) == -16384)
        #expect(frontend.stickAxis(index: LibretroABI.AnalogStick.right.rawValue, axis: LibretroABI.ANALOG_AXIS_Y, player: 1) == 16384)
    }

    @Test func clearingAPlayerCentresItsSticks() {
        frontend.setStick(.left, x: 1, y: 1, player: 1)
        frontend.clearAllButtons(player: 1)

        #expect(frontend.stickAxis(index: 0, axis: 0, player: 1) == 0)
        #expect(frontend.stickAxis(index: 0, axis: 1, player: 1) == 0)
    }

    @Test func unknownIndexOrPlayerReadsAsCentred() {
        #expect(frontend.stickAxis(index: 2, axis: 0, player: 0) == 0)
        #expect(frontend.stickAxis(index: 0, axis: 0, player: LibretroFrontend.maxPlayers) == 0)
    }
}

@MainActor
struct AnalogStickLayoutTests {

    @Test func playStationFollowsTheSwitch() {
        #expect(LibretroTouchControllerView.Layout.forCore(.pcsxRearmed, analogSticks: false) == .standard)
        #expect(LibretroTouchControllerView.Layout.forCore(.pcsxRearmed, analogSticks: true) == .dualShock)
    }

    @Test func pspAlwaysHasOneStickAndNoSecondShoulderRow() {
        let layout = LibretroTouchControllerView.Layout.forCore(.ppsspp, analogSticks: false)
        #expect(layout == .psp)
        #expect(layout.sticks == [.left])
        #expect(layout.shoulderRows.count == 1)
    }

    @Test func otherSystemsIgnoreTheSwitch() {
        #expect(LibretroTouchControllerView.Layout.forCore(.flycast, analogSticks: true) == .dreamcast)
        #expect(LibretroTouchControllerView.Layout.forCore(.genesisPlusGX, analogSticks: true) == .genesis)
        #expect(LibretroTouchControllerView.Layout.forCore(.beetlePCEFast, analogSticks: true) == .pcEngine)
    }

    @Test func dualShockHasBothSticks() {
        #expect(LibretroTouchControllerView.Layout.dualShock.sticks == [.left, .right])
        #expect(LibretroTouchControllerView.Layout.standard.sticks.isEmpty)
    }
}

@MainActor
struct AnalogStickTouchTests {

    private let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test func centreIsNeutral() {
        let vector = LibretroTouchControllerView.stickVector(for: CGPoint(x: 50, y: 50), in: bounds)
        #expect(vector == .zero)
    }

    @Test func fullDeflectionIsReachedInsideTheRing() {
        let vector = LibretroTouchControllerView.stickVector(for: CGPoint(x: 85, y: 50), in: bounds)
        #expect(abs(vector.dx - 1) < 0.0001)
        #expect(vector.dy == 0)
    }

    @Test func dragsPastTheRingAreCappedToTheUnitCircle() {
        let vector = LibretroTouchControllerView.stickVector(for: CGPoint(x: 200, y: 200), in: bounds)
        let length = (vector.dx * vector.dx + vector.dy * vector.dy).squareRoot()
        #expect(abs(length - 1) < 0.0001)
        #expect(vector.dx > 0 && vector.dy > 0)
    }

    @Test func upIsNegative() {
        let vector = LibretroTouchControllerView.stickVector(for: CGPoint(x: 50, y: 30), in: bounds)
        #expect(vector.dy < 0)
    }
}

@MainActor
struct PlayStationPortDeviceTests {

    @Test func plainPadWithoutSticksOrRumble() {
        #expect(LibretroSession.playerOneDevice(rumble: false, analogSticks: false) == LibretroABI.DEVICE_JOYPAD)
    }

    @Test func dualShockForSticksOrRumble() {
        #expect(LibretroSession.playerOneDevice(rumble: false, analogSticks: true) == LibretroABI.DEVICE_PSE_DUALSHOCK)
        #expect(LibretroSession.playerOneDevice(rumble: true, analogSticks: false) == LibretroABI.DEVICE_PSE_DUALSHOCK)
    }
}

/// Models one emulated frame the way `LibretroFrontend` drives it: the core
/// polls `isPressingCombo` during `retro_run`, may synchronously report a
/// toggle through `coreReported` from inside that same call, and only then
/// does `frameDidRun` run.
@MainActor
private func runFrame(_ analogSwitch: inout DualShockAnalogSwitch, reports message: Bool? = nil) -> Bool {
    let wasPressing = analogSwitch.isPressingCombo
    if let message {
        analogSwitch.coreReported(analog: message)
    }
    analogSwitch.frameDidRun()
    return wasPressing
}

@MainActor
struct DualShockAnalogSwitchTests {

    @Test func idleSwitchPressesNothing() {
        #expect(!DualShockAnalogSwitch().isPressingCombo)
    }

    @Test func requestHoldsTheComboForOneFrame() {
        var analogSwitch = DualShockAnalogSwitch()
        analogSwitch.request(analog: true)
        #expect(analogSwitch.isPressingCombo)

        _ = runFrame(&analogSwitch)
        #expect(!analogSwitch.isPressingCombo)
    }

    @Test func analogOnEndsTheRequest() {
        var analogSwitch = DualShockAnalogSwitch()
        analogSwitch.request(analog: true)

        // Frame 1: the combo is held, the core reports the target mode.
        let pressed = runFrame(&analogSwitch, reports: true)
        #expect(pressed)
        #expect(!analogSwitch.isPressingCombo)
    }

    @Test func analogOffRetriesAfterOneReleasedFrame() {
        var analogSwitch = DualShockAnalogSwitch()
        analogSwitch.request(analog: true)

        // Frame 1: combo held, core reports the opposite of the target.
        let pressed1 = runFrame(&analogSwitch, reports: false)
        #expect(pressed1)
        #expect(!analogSwitch.isPressingCombo)

        // Frame 2: the core must see the combo released this frame.
        let pressed2 = runFrame(&analogSwitch)
        #expect(!pressed2)

        // Frame 3: only now is the combo pressed again.
        #expect(analogSwitch.isPressingCombo)
    }

    @Test func givesUpAfterTheRetry() {
        var analogSwitch = DualShockAnalogSwitch()
        analogSwitch.request(analog: true)

        _ = runFrame(&analogSwitch, reports: false)
        _ = runFrame(&analogSwitch)
        // Frame 3: the retry press.
        #expect(analogSwitch.isPressingCombo)
        _ = runFrame(&analogSwitch, reports: false)

        #expect(!analogSwitch.isPressingCombo)
    }

    @Test func togglesWithoutARequestAreIgnored() {
        var analogSwitch = DualShockAnalogSwitch()
        _ = runFrame(&analogSwitch, reports: false)
        #expect(!analogSwitch.isPressingCombo)
    }

    @Test func readsOnlyTheToggleMessages() {
        #expect(DualShockAnalogSwitch.reportedMode(in: "ANALOG ON") == true)
        #expect(DualShockAnalogSwitch.reportedMode(in: "ANALOG OFF") == false)
        #expect(DualShockAnalogSwitch.reportedMode(in: "Disk 1 inserted") == nil)
    }

    @Test func frontendSendsOnlyTheComboWhilePressing() {
        let frontend = LibretroFrontend.shared
        defer { frontend.clearAllButtons(player: 0) }
        frontend.setButton(.a, pressed: true, player: 0)
        frontend.requestDualShockMode(analog: true)
        defer { frontend.coreDidShowMessage("ANALOG ON") }

        #expect(frontend.isButtonPressed(Int(LibretroABI.JoypadButton.l.rawValue), player: 0))
        #expect(frontend.isButtonPressed(Int(LibretroABI.JoypadButton.r.rawValue), player: 0))
        #expect(frontend.isButtonPressed(Int(LibretroABI.JoypadButton.r3.rawValue), player: 0))
        #expect(!frontend.isButtonPressed(Int(LibretroABI.JoypadButton.a.rawValue), player: 0))
    }
}

struct AnalogSticksPreferenceStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func offByDefault() {
        let store = UserDefaultsAnalogSticksPreferenceStore(userDefaults: makeDefaults())
        #expect(!store.isEnabled)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        UserDefaultsAnalogSticksPreferenceStore(userDefaults: defaults).isEnabled = true
        let reopened = UserDefaultsAnalogSticksPreferenceStore(userDefaults: defaults)
        #expect(reopened.isEnabled)
    }
}

@MainActor
struct ShoulderRowLayoutTests {

    @Test func dualShockHasTwoShoulderRows() {
        let rows = LibretroTouchControllerView.Layout.dualShock.shoulderRows
        #expect(rows.count == 2)
        #expect(rows[0].left == .l && rows[0].right == .r)
        #expect(rows[1].left == .l2 && rows[1].right == .r2)
    }

    @Test func pspHasOneShoulderRow() {
        let rows = LibretroTouchControllerView.Layout.psp.shoulderRows
        #expect(rows.count == 1)
        #expect(rows[0].left == .l && rows[0].right == .r)
    }
}

struct PhysicalStickInversionTests {

    @Test func upOnTheControllerBecomesNegativeYForLibretro() {
        let mapped = LibretroControllerInput.libretroStickValue(x: 0, y: 1)
        #expect(mapped.y == -1)
    }

    @Test func xPassesThrough() {
        let mapped = LibretroControllerInput.libretroStickValue(x: 0.5, y: 0)
        #expect(mapped.x == 0.5)
        #expect(mapped.y == 0)
    }
}
