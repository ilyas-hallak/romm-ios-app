import Testing
import Foundation
@testable import romm

struct RemoteControllerCodecTests {

    @Test func decodesWhatItEncoded() {
        var codec = RemoteControllerCodec()
        let data = RemoteControllerCodec.encode(.button(.a, pressed: true))
        #expect(codec.decode(data ?? Data()) == [.button(.a, pressed: true)])
    }

    @Test func readsSeveralMessagesFromOneChunk() {
        var codec = RemoteControllerCodec()
        var chunk = Data()
        chunk.append(RemoteControllerCodec.encode(.hello(padName: "Pad"))!)
        chunk.append(RemoteControllerCodec.encode(.button(.left, pressed: true))!)
        #expect(codec.decode(chunk) == [.hello(padName: "Pad"), .button(.left, pressed: true)])
    }

    /// TCP can split a message anywhere, so half of one has to wait for the rest.
    @Test func holdsHalfAMessageUntilTheRestArrives() {
        var codec = RemoteControllerCodec()
        let encoded = RemoteControllerCodec.encode(.button(.start, pressed: false))!
        let cut = encoded.count / 2
        #expect(codec.decode(encoded.prefix(cut)).isEmpty)
        #expect(codec.decode(encoded.suffix(from: cut)) == [.button(.start, pressed: false)])
    }

    @Test func skipsALineItCannotRead() {
        var codec = RemoteControllerCodec()
        var chunk = Data("not json\n".utf8)
        chunk.append(RemoteControllerCodec.encode(.button(.b, pressed: true))!)
        #expect(codec.decode(chunk) == [.button(.b, pressed: true)])
    }

    /// A peer that never sends a newline must not be able to grow the buffer
    /// without end.
    @Test func dropsAnEndlessLine() {
        var codec = RemoteControllerCodec()
        let flood = Data(repeating: UInt8(ascii: "x"), count: RemoteControllerCodec.maxLineLength + 1)
        #expect(codec.decode(flood).isEmpty)
        // The flood is gone rather than sitting in front of the next message.
        #expect(codec.decode(RemoteControllerCodec.encode(.button(.y, pressed: true))!) == [.button(.y, pressed: true)])
    }
}

struct RemoteGamepadButtonTests {

    @Test func everyButtonSurvivesTheTripThroughLibretro() {
        for button in RemoteGamepadButton.allCases {
            #expect(RemoteGamepadButton(libretroButton: button.libretroButton) == button)
        }
    }

    /// No two pad buttons may drive the same libretro button, or one press
    /// would silently release another.
    @Test func noTwoButtonsShareALibretroButton() {
        let mapped = Set(RemoteGamepadButton.allCases.map(\.libretroButton))
        #expect(mapped.count == RemoteGamepadButton.allCases.count)
    }

    @Test func thumbstickClicksHaveNoPadButton() {
        #expect(RemoteGamepadButton(libretroButton: .l3) == nil)
        #expect(RemoteGamepadButton(libretroButton: .r3) == nil)
    }
}

@MainActor
struct LibretroPlayerPortTests {

    private func makeFrontend() -> LibretroFrontend {
        let frontend = LibretroFrontend.shared
        frontend.clearAllButtons()
        return frontend
    }

    @Test func playersDoNotShareTheirButtons() {
        let frontend = makeFrontend()
        frontend.setButton(.a, pressed: true, player: 1)
        #expect(frontend.isButtonPressed(Int(LibretroABI.JoypadButton.a.rawValue), player: 1))
        #expect(!frontend.isButtonPressed(Int(LibretroABI.JoypadButton.a.rawValue), player: 0))
        frontend.clearAllButtons()
    }

    @Test func clearingOnePlayerLeavesTheOtherAlone() {
        let frontend = makeFrontend()
        frontend.setButton(.start, pressed: true, player: 0)
        frontend.setButton(.start, pressed: true, player: 1)
        frontend.clearAllButtons(player: 1)
        #expect(frontend.isButtonPressed(Int(LibretroABI.JoypadButton.start.rawValue), player: 0))
        #expect(!frontend.isButtonPressed(Int(LibretroABI.JoypadButton.start.rawValue), player: 1))
        frontend.clearAllButtons()
    }

    /// A core is free to poll a port we do not carry, and must read zero there
    /// rather than crash us.
    @Test func portsBeyondTheLastPlayerReadEmpty() {
        let frontend = makeFrontend()
        #expect(!frontend.isButtonPressed(0, player: LibretroFrontend.maxPlayers))
        #expect(!frontend.isButtonPressed(99, player: 0))
    }
}

// MARK: - Manager

@MainActor
private final class FakeRemoteControllerHostService: PRemoteControllerHostService {
    var onButton: ((RemoteGamepadButton, Bool) -> Void)?
    var onPadChanged: ((String?) -> Void)?
    private(set) var advertisedName: String?

    func startAdvertising(as hostName: String) { advertisedName = hostName }
    func stopAdvertising() { advertisedName = nil }

    func simulatePadJoined(_ name: String) {
        onPadChanged?(name)
    }

    func simulatePadLeft() {
        onPadChanged?(nil)
    }
}

@MainActor
private final class SpySecondPlayerInput: PSecondPlayerInput {
    private(set) var connectionChanges: [Bool] = []
    private(set) var buttons: [(RemoteGamepadButton, Bool)] = []

    func setSecondPlayerConnected(_ connected: Bool) { connectionChanges.append(connected) }
    func setSecondPlayerButton(_ button: RemoteGamepadButton, pressed: Bool) {
        buttons.append((button, pressed))
    }
}

private final class InMemorySecondControllerPreference: PSecondControllerPreference {
    var acceptsRemotePad = false
}

@MainActor
struct SecondControllerManagerTests {

    private func makeManager() -> (SecondControllerManager, FakeRemoteControllerHostService) {
        let service = FakeRemoteControllerHostService()
        let manager = SecondControllerManager(
            hostService: service,
            preference: InMemorySecondControllerPreference()
        )
        return (manager, service)
    }

    @Test func buttonsReachTheRunningGame() {
        let (manager, service) = makeManager()
        let input = SpySecondPlayerInput()
        manager.setInput(input)
        service.simulatePadJoined("Pad")
        service.onButton?(.a, true)
        #expect(input.buttons.count == 1)
        #expect(input.buttons.first?.0 == .a)
        #expect(input.buttons.first?.1 == true)
    }

    /// A pad that joined before the game started still has to be found.
    @Test func aGameStartedLaterPicksUpThePadThatIsAlreadyThere() {
        let (manager, service) = makeManager()
        service.simulatePadJoined("Pad")
        let input = SpySecondPlayerInput()
        manager.setInput(input)
        #expect(input.connectionChanges == [true])
    }

    @Test func aPadThatLeavesIsReportedSoItsButtonsCanBeLifted() {
        let (manager, service) = makeManager()
        let input = SpySecondPlayerInput()
        manager.setInput(input)
        service.simulatePadJoined("Pad")
        service.simulatePadLeft()
        #expect(input.connectionChanges == [false, true, false])
        #expect(manager.padName == nil)
    }

    @Test func handingTheInputBackDisconnectsIt() {
        let (manager, service) = makeManager()
        let input = SpySecondPlayerInput()
        manager.setInput(input)
        service.simulatePadJoined("Pad")
        manager.setInput(nil)
        #expect(input.connectionChanges.last == false)
    }

    @Test func advertisingFollowsTheSetting() {
        let (manager, service) = makeManager()
        manager.setAcceptsRemotePad(true)
        #expect(service.advertisedName != nil)
        manager.setAcceptsRemotePad(false)
        #expect(service.advertisedName == nil)
    }

    @Test func nothingIsAdvertisedUntilTheSettingIsOn() {
        let (manager, service) = makeManager()
        manager.startIfEnabled()
        #expect(service.advertisedName == nil)
    }
}
