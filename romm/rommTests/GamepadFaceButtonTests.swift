import Testing
import Foundation
import DeltaCore
@testable import romm

struct GamepadFaceButtonPreferenceStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func facesAreNotSwappedInitially() {
        let store = UserDefaultsGamepadFaceButtonPreferenceStore(userDefaults: makeDefaults())
        #expect(!store.isSwapped)
    }

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        UserDefaultsGamepadFaceButtonPreferenceStore(userDefaults: defaults).isSwapped = true
        let reopened = UserDefaultsGamepadFaceButtonPreferenceStore(userDefaults: defaults)
        #expect(reopened.isSwapped)
    }
}

struct LibretroFaceButtonLayoutTests {

    /// The layout the app has always used: bottom is B, as on a SNES pad.
    @Test func unswappedKeepsTheSNESLayout() {
        #expect(LibretroControllerInput.faceButton(.bottom, swapped: false) == .b)
        #expect(LibretroControllerInput.faceButton(.right, swapped: false) == .a)
        #expect(LibretroControllerInput.faceButton(.left, swapped: false) == .y)
        #expect(LibretroControllerInput.faceButton(.top, swapped: false) == .x)
    }

    @Test func swappingExchangesBothPairs() {
        #expect(LibretroControllerInput.faceButton(.bottom, swapped: true) == .a)
        #expect(LibretroControllerInput.faceButton(.right, swapped: true) == .b)
        #expect(LibretroControllerInput.faceButton(.left, swapped: true) == .x)
        #expect(LibretroControllerInput.faceButton(.top, swapped: true) == .y)
    }
}

struct FaceButtonInputMappingTests {

    private func makeMapping() -> GameControllerInputMapping {
        var mapping = GameControllerInputMapping(gameControllerInputType: .mfi)
        mapping.set(StandardGameControllerInput.a, forControllerInput: MFiGameController.Input.a)
        mapping.set(StandardGameControllerInput.b, forControllerInput: MFiGameController.Input.b)
        mapping.set(StandardGameControllerInput.x, forControllerInput: MFiGameController.Input.x)
        mapping.set(StandardGameControllerInput.y, forControllerInput: MFiGameController.Input.y)
        mapping.set(StandardGameControllerInput.start, forControllerInput: MFiGameController.Input.menu)
        return mapping
    }

    private func target(_ mapping: GameControllerInputMappingProtocol?, _ input: MFiGameController.Input) -> String? {
        mapping?.input(forControllerInput: input)?.stringValue
    }

    @Test func swapsBothFaceButtonPairs() {
        let swapped = FaceButtonInputMapping.swappingFaceButtons(of: makeMapping())
        #expect(target(swapped, .a) == "b")
        #expect(target(swapped, .b) == "a")
        #expect(target(swapped, .x) == "y")
        #expect(target(swapped, .y) == "x")
    }

    @Test func leavesEveryOtherInputAlone() {
        let swapped = FaceButtonInputMapping.swappingFaceButtons(of: makeMapping())
        #expect(target(swapped, .menu) == "start")
    }

    /// Swapping twice has to land back on the original, otherwise the mapping
    /// would drift every time a controller reconnects.
    @Test func swappingTwiceRestoresTheOriginal() {
        let once = FaceButtonInputMapping.swappingFaceButtons(of: makeMapping())
        let twice = FaceButtonInputMapping.swappingFaceButtons(of: once)
        #expect(target(twice, .a) == "a")
        #expect(target(twice, .b) == "b")
        #expect(target(twice, .x) == "x")
        #expect(target(twice, .y) == "y")
    }

    /// A mapping that leaves a face button unassigned must not gain one.
    @Test func keepsUnmappedButtonsUnmapped() {
        var mapping = GameControllerInputMapping(gameControllerInputType: .mfi)
        mapping.set(StandardGameControllerInput.a, forControllerInput: MFiGameController.Input.a)
        let swapped = FaceButtonInputMapping.swappingFaceButtons(of: mapping)
        #expect(target(swapped, .a) == nil)
        #expect(target(swapped, .b) == "a")
    }

    @Test func passesNilThrough() {
        #expect(FaceButtonInputMapping.swappingFaceButtons(of: nil) == nil)
    }
}
