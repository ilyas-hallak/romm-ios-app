import Testing
import DeltaCore
@testable import romm

struct EmulatorMenuFocusTests {
    private enum Item: Hashable {
        case quit, done, slot, load, save, undo
    }

    private func makeFocus(initial: Item = .load) -> EmulatorMenuFocus<Item> {
        EmulatorMenuFocus(
            rows: [[.quit, .done], [.slot], [.load, .save, .undo]],
            initial: initial,
            adjustableItems: [.slot]
        )
    }

    @Test func firstCommandOnlyRevealsTheFocus() {
        var focus = makeFocus()
        #expect(!focus.isFocused(.load))
        #expect(focus.handle(.confirm) == .none)
        #expect(focus.isFocused(.load))
    }

    @Test func backDismissesEvenBeforeTheFocusIsShown() {
        var focus = makeFocus()
        #expect(focus.handle(.back) == .dismiss)
        #expect(!focus.isVisible)
    }

    @Test func confirmActivatesTheFocusedItem() {
        var focus = makeFocus()
        _ = focus.handle(.down)
        #expect(focus.handle(.confirm) == .activate(.load))
    }

    @Test func movesWithinARowWithoutWrapping() {
        var focus = makeFocus()
        _ = focus.handle(.right)
        _ = focus.handle(.right)
        _ = focus.handle(.right)
        #expect(focus.focused == .undo)
        _ = focus.handle(.right)
        #expect(focus.focused == .undo)
    }

    @Test func clampsTheColumnWhenTheNextRowIsShorter() {
        var focus = makeFocus()
        _ = focus.handle(.confirm)
        _ = focus.handle(.right)
        _ = focus.handle(.right)
        #expect(focus.focused == .undo)
        _ = focus.handle(.up)
        #expect(focus.focused == .slot)
        _ = focus.handle(.up)
        #expect(focus.focused == .quit)
    }

    @Test func staysPutAtTheEdges() {
        var focus = makeFocus(initial: .quit)
        _ = focus.handle(.up)
        _ = focus.handle(.up)
        #expect(focus.focused == .quit)
        _ = focus.handle(.left)
        #expect(focus.focused == .quit)
    }

    @Test func adjustableItemsTakeLeftAndRightAsValueChanges() {
        var focus = makeFocus(initial: .slot)
        _ = focus.handle(.confirm)
        #expect(focus.handle(.left) == .adjust(.slot, by: -1))
        #expect(focus.handle(.right) == .adjust(.slot, by: 1))
        #expect(focus.focused == .slot)
    }
}

struct EmulatorMenuStickAxisTests {
    @Test func firesOncePerPush() {
        var axis = EmulatorMenuStickAxis(negative: .down, positive: .up)
        #expect(axis.update(0.4) == nil)
        #expect(axis.update(0.6) == .up)
        #expect(axis.update(0.9) == nil)
        #expect(axis.update(0.4) == nil)
        #expect(axis.update(0.1) == nil)
        #expect(axis.update(-0.7) == .down)
    }

    @Test func needsToComeBackBelowTheReleaseThreshold() {
        var axis = EmulatorMenuStickAxis(negative: .left, positive: .right)
        #expect(axis.update(0.6) == .right)
        #expect(axis.update(0.35) == nil)
        #expect(axis.update(0.6) == nil)
    }

    @Test func halfReleasedAfterTheOtherHalfTookOverDoesNotCentre() {
        var axis = EmulatorMenuStickAxis(negative: .left, positive: .right)
        #expect(axis.update(half: .positive, magnitude: 0.8) == .right)
        #expect(axis.update(half: .negative, magnitude: 0.2) == nil)
        #expect(axis.update(half: .negative, magnitude: 0.8) == .left)
        // A late release of the right half must not re-arm the left push.
        #expect(axis.update(half: .positive, magnitude: 0) == nil)
        #expect(axis.update(half: .negative, magnitude: 0.9) == nil)
    }

    @Test func halfReleaseCentresTheAxis() {
        var axis = EmulatorMenuStickAxis(negative: .left, positive: .right)
        #expect(axis.update(half: .positive, magnitude: 0.8) == .right)
        #expect(axis.update(half: .positive, magnitude: 0) == nil)
        #expect(axis.update(half: .positive, magnitude: 0.8) == .right)
    }
}

struct EmulatorMenuButtonMappingTests {
    @Test(arguments: [false, true])
    func nativeDPadMapsToDirections(swapped: Bool) {
        #expect(NativeMenuInput.menuCommand(for: .up, faceButtonsSwapped: swapped) == .up)
        #expect(NativeMenuInput.menuCommand(for: .down, faceButtonsSwapped: swapped) == .down)
        #expect(NativeMenuInput.menuCommand(for: .left, faceButtonsSwapped: swapped) == .left)
        #expect(NativeMenuInput.menuCommand(for: .right, faceButtonsSwapped: swapped) == .right)
    }

    @Test func nativeFaceButtonsFollowTheSwap() {
        #expect(NativeMenuInput.menuCommand(for: .a, faceButtonsSwapped: false) == .confirm)
        #expect(NativeMenuInput.menuCommand(for: .b, faceButtonsSwapped: false) == .back)
        #expect(NativeMenuInput.menuCommand(for: .a, faceButtonsSwapped: true) == .back)
        #expect(NativeMenuInput.menuCommand(for: .b, faceButtonsSwapped: true) == .confirm)
    }

    @Test func nativeIgnoresButtonsWithoutAMenuMeaning() {
        #expect(NativeMenuInput.menuCommand(for: .x, faceButtonsSwapped: false) == nil)
        #expect(NativeMenuInput.menuCommand(for: .l1, faceButtonsSwapped: false) == nil)
        #expect(NativeMenuInput.menuCommand(for: .menu, faceButtonsSwapped: false) == nil)
    }

    /// The button labelled A drives `.b` in both swap states, so it has to
    /// confirm whichever way round the pad is.
    @Test(arguments: [false, true])
    func libretroConfirmIsTheButtonLabelledA(swapped: Bool) {
        let labelledA: LibretroControllerInput.FaceButtonPosition = swapped ? .right : .bottom
        let button = LibretroControllerInput.faceButton(labelledA, swapped: swapped)
        #expect(LibretroControllerInput.menuCommand(for: button) == .confirm)
    }

    @Test func libretroBackAndStartCloseTheMenu() {
        #expect(LibretroControllerInput.menuCommand(for: .a) == .back)
        #expect(LibretroControllerInput.menuCommand(for: .start) == .back)
        #expect(LibretroControllerInput.menuCommand(for: .select) == nil)
        #expect(LibretroControllerInput.menuCommand(for: .up) == .up)
    }
}
