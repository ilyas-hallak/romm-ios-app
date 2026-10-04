#if !APP_STORE
import Testing
import DeltaCore
@testable import romm

struct RemoteSkinGameControllerTests {

    private func makeSut() -> RemoteSkinGameController {
        RemoteSkinGameController(name: "Pad", playerIndex: 0, gameType: .n64)
    }

    private func key(_ inputName: String) -> AnyInput {
        AnyInput(stringValue: inputName, intValue: nil, type: .controller(.controllerSkin))
    }

    @Test func aSkinInputReachesTheCoreUnderItsOwnName() {
        let sut = makeSut()
        sut.set("cUp", value: 1)
        #expect(sut.activatedInputs[key("cUp")] == 1)
    }

    @Test func aValueAboveOneIsClamped() {
        let sut = makeSut()
        sut.set("cUp", value: 2)
        #expect(sut.activatedInputs[key("cUp")] == 1)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteValuesAreDropped(value: Double) {
        let sut = makeSut()
        sut.set("cUp", value: value)
        #expect(sut.activatedInputs.isEmpty)
    }

    @Test func anUnknownInputNameIsDropped() {
        let sut = makeSut()
        sut.set("menu", value: 1)
        #expect(sut.activatedInputs.isEmpty)
    }

    @Test func zeroReleasesAHeldInput() {
        let sut = makeSut()
        sut.set("cUp", value: 1)
        sut.set("cUp", value: 0)
        #expect(sut.activatedInputs.isEmpty)
    }

    @Test func releaseAllLiftsEverythingStillHeld() {
        let sut = makeSut()
        sut.set("cUp", value: 1)
        sut.set("cDown", value: 1)
        sut.releaseAll()
        #expect(sut.activatedInputs.isEmpty)
    }
}
#endif
