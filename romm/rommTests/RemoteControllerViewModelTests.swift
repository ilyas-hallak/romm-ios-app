import Testing
import Foundation
@testable import romm

@MainActor
private final class FakeRemoteControllerClientService: PRemoteControllerClientService {
    var onHostsChanged: (([RemoteControllerHost]) -> Void)?
    var onStateChanged: ((RemoteControllerLinkState) -> Void)?

    private(set) var stopBrowsingCalled = false
    private(set) var disconnectCount = 0
    private(set) var connectedTo: RemoteControllerHost?
    private(set) var connectedAs: String?
    private(set) var sentButtons: [(RemoteGamepadButton, Bool)] = []

    func startBrowsing() {}
    func stopBrowsing() { stopBrowsingCalled = true }

    func connect(to host: RemoteControllerHost, as padName: String) {
        connectedTo = host
        connectedAs = padName
    }

    func disconnect() { disconnectCount += 1 }

    func send(_ button: RemoteGamepadButton, pressed: Bool) {
        sentButtons.append((button, pressed))
    }

    func simulateState(_ state: RemoteControllerLinkState) { onStateChanged?(state) }
    func simulateHosts(_ hosts: [RemoteControllerHost]) { onHostsChanged?(hosts) }
}

@MainActor
struct RemoteControllerViewModelTests {

    private func makeSut(padName: String = "Pad") -> (RemoteControllerViewModel, FakeRemoteControllerClientService) {
        let service = FakeRemoteControllerClientService()
        let viewModel = RemoteControllerViewModel(service: service, padName: padName)
        return (viewModel, service)
    }

    @Test func stopResetsStateAndHostsEvenWhileConnected() {
        let (viewModel, service) = makeSut()
        service.simulateState(.connected(hostName: "Host"))
        service.simulateHosts([RemoteControllerHost(id: "1", name: "Host")])

        viewModel.stop()

        #expect(viewModel.state == .idle)
        #expect(viewModel.hosts.isEmpty)
        #expect(service.disconnectCount == 1)
        #expect(service.stopBrowsingCalled)
    }

    @Test func connectPassesTheInjectedPadName() {
        let (viewModel, service) = makeSut(padName: "Living room phone")
        let host = RemoteControllerHost(id: "1", name: "Host")

        viewModel.connect(to: host)

        #expect(service.connectedTo == host)
        #expect(service.connectedAs == "Living room phone")
    }

    @Test(arguments: [
        (RemoteControllerLinkState.idle, false, nil as String?, nil as String?),
        (.searching, false, nil, nil),
        (.connecting(hostName: "Host"), false, "Host", nil),
        (.connected(hostName: "Host"), true, "Host", nil),
        (.failed(message: "Lost connection"), false, nil, "Lost connection"),
    ])
    func stateMapsToTheViewModelsProperties(
        state: RemoteControllerLinkState,
        expectedIsPlaying: Bool,
        expectedHostName: String?,
        expectedErrorMessage: String?
    ) {
        let (viewModel, service) = makeSut()

        service.simulateState(state)

        #expect(viewModel.isPlaying == expectedIsPlaying)
        #expect(viewModel.hostName == expectedHostName)
        #expect(viewModel.errorMessage == expectedErrorMessage)
    }

    @Test func setButtonSendsItToTheService() {
        let (viewModel, service) = makeSut()

        viewModel.setButton(.a, pressed: true)
        viewModel.setButton(.a, pressed: false)

        #expect(service.sentButtons.count == 2)
        #expect(service.sentButtons[0].0 == .a)
        #expect(service.sentButtons[0].1 == true)
        #expect(service.sentButtons[1].1 == false)
    }
}
