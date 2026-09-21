import Foundation
import Observation
import UIKit

/// Drives this phone while it acts as a pad for another one.
@Observable
@MainActor
final class RemoteControllerViewModel {

    private(set) var hosts: [RemoteControllerHost] = []
    private(set) var state: RemoteControllerLinkState = .idle

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
        service.onStateChanged = { [weak self] state in self?.state = state }
    }

    func start() {
        service.startBrowsing()
    }

    func stop() {
        service.disconnect()
        service.stopBrowsing()
        state = .idle
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
}
