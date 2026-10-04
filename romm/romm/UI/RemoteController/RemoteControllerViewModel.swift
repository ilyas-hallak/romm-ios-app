import Foundation
import Observation
import UIKit

/// Drives this phone while it acts as a pad for another one.
@Observable
@MainActor
final class RemoteControllerViewModel {

    private(set) var hosts: [RemoteControllerHost] = []
    private(set) var state: RemoteControllerLinkState = .idle
    /// What the host wants drawn. Back to the generic pad once the link is gone,
    /// the next host may not say.
    private(set) var layout: RemotePadLayout = .standard

    var isPlaying: Bool {
        if case .connected = state { return true }
        return false
    }

    var hostName: String? {
        switch state {
        case .connecting(let name), .connected(let name): return name
        default: return nil
        }
    }

    var errorMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    private let service: PRemoteControllerClientService
    private let padName: String

    /// Both are built here rather than defaulted in the signature, a default
    /// expression would be evaluated off the main actor at the call site.
    init(service: PRemoteControllerClientService? = nil, padName: String? = nil) {
        let service = service ?? RemoteControllerClientService()
        self.service = service
        self.padName = padName ?? UIDevice.current.name
        service.onHostsChanged = { [weak self] hosts in self?.hosts = hosts }
        service.onStateChanged = { [weak self] state in
            guard let self else { return }
            self.state = state
            if !self.isPlaying { self.layout = .standard }
        }
        service.onLayoutChanged = { [weak self] layout in self?.layout = layout }
    }

    func start() {
        service.startBrowsing()
    }

    func stop() {
        service.disconnect()
        service.stopBrowsing()
        state = .idle
        layout = .standard
        hosts = []
    }

    func connect(to host: RemoteControllerHost) {
        service.connect(to: host, as: padName)
    }

    func disconnect() {
        service.disconnect()
    }

    func setButton(_ button: RemoteGamepadButton, pressed: Bool) {
        service.send(button, pressed: pressed)
    }

    func setGameInput(_ name: String, value: Double) {
        service.sendGameInput(name, value: value)
    }
}
