import Foundation
import Network

/// Turns this phone into a pad for a host on the same network.
///
/// Browsing and the connection are kept apart on purpose: the browser stays
/// alive while connected, so a host that goes away is noticed and the list
/// behind the player is still current when they disconnect.
@MainActor
final class RemoteControllerClientService: PRemoteControllerClientService {

    var onHostsChanged: (([RemoteControllerHost]) -> Void)?
    var onStateChanged: ((RemoteControllerLinkState) -> Void)?
    var onLayoutChanged: ((RemotePadLayout) -> Void)?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    /// Endpoints keyed by the host id the UI hands back, so the UI never has to
    /// carry a network type around.
    private var endpoints: [String: NWEndpoint] = [:]
    private var codec = RemoteControllerCodec()

    func startBrowsing() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: RemoteControllerBonjour.serviceType,
            domain: RemoteControllerBonjour.domain
        )
        let browser = NWBrowser(for: descriptor, using: .tcp)
        // See RemoteControllerHostService: the queue is the main one, so the
        // handlers are already where they need to be.
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.updateHosts(from: results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            // Waiting: see the connection below, same permission case.
            let error: NWError
            switch state {
            case .failed(let failure), .waiting(let failure): error = failure
            default: return
            }
            MainActor.assumeIsolated {
                self?.onStateChanged?(.failed(message: error.localizedDescription))
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        onStateChanged?(.searching)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        endpoints.removeAll()
        onHostsChanged?([])
    }

    func connect(to host: RemoteControllerHost, as padName: String) {
        guard let endpoint = endpoints[host.id] else {
            onStateChanged?(.failed(message: "\(host.name) is no longer on the network"))
            return
        }
        connection?.cancel()
        let connection = NWConnection(to: endpoint, using: Self.parameters)
        self.connection = connection
        codec = RemoteControllerCodec()
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.connection === connection else { return }
                switch state {
                case .ready:
                    self.write(.hello(padName: padName))
                    self.receive(on: connection)
                    self.onStateChanged?(.connected(hostName: host.name))
                // Waiting is where a denied local network permission ends up,
                // it would otherwise sit on "connecting" for good.
                case .failed(let error), .waiting(let error):
                    connection.cancel()
                    self.connection = nil
                    self.onStateChanged?(.failed(message: error.localizedDescription))
                case .cancelled:
                    self.connection = nil
                    self.onStateChanged?(.searching)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        onStateChanged?(.connecting(hostName: host.name))
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        onStateChanged?(browser == nil ? .idle : .searching)
    }

    func send(_ button: RemoteGamepadButton, pressed: Bool) {
        write(.button(button, pressed: pressed))
    }

    func sendGameInput(_ name: String, value: Double) {
        write(.gameInput(name: name, value: value))
    }

    // MARK: - Private

    /// A stick sends a stream of small writes, which Nagle's algorithm would
    /// hold back and bundle. Every one of them is a frame the player feels.
    private static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        return NWParameters(tls: nil, tcp: tcp)
    }

    /// Only the layout comes back from the host. A host that closes its end is
    /// gone, cancelling sends the pad back to the list.
    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, self.connection === connection else { return }
                if let data, !data.isEmpty {
                    for case .layout(let layout) in self.codec.decode(data) {
                        self.onLayoutChanged?(layout)
                    }
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                self.receive(on: connection)
            }
        }
    }

    private func updateHosts(from results: Set<NWBrowser.Result>) {
        var endpoints: [String: NWEndpoint] = [:]
        var hosts: [RemoteControllerHost] = []
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            endpoints[name] = result.endpoint
            hosts.append(RemoteControllerHost(id: name, name: name))
        }
        self.endpoints = endpoints
        onHostsChanged?(hosts.sorted { $0.name < $1.name })
    }

    private func write(_ message: RemoteControllerMessage) {
        guard let connection, let data = RemoteControllerCodec.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}
