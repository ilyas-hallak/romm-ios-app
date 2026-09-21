import Foundation
import Network

/// Takes a phone on the local network as a second pad.
///
/// Advertises a Bonjour service and holds one pad at a time. A second pad that
/// joins takes the place of the first, which is the friendlier reading of it:
/// a phone that dropped off the network and came back would otherwise be locked
/// out by its own stale connection.
@MainActor
final class RemoteControllerHostService: PRemoteControllerHostService {

    private(set) var connectedPadName: String?
    var onButton: ((RemoteGamepadButton, Bool) -> Void)?
    var onPadChanged: ((String?) -> Void)?

    private var listener: NWListener?
    private var connection: NWConnection?
    private var codec = RemoteControllerCodec()

    func startAdvertising(as hostName: String) {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: hostName,
                type: RemoteControllerBonjour.serviceType
            )
            // Every handler below runs on the queue the listener and its
            // connections are started on, which is why they can assume the main
            // actor instead of hopping onto it: a button press should reach the
            // core on the runloop turn it arrived in.
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard case .failed(let error) = state else { return }
                Logger.ui.error("Remote pad listener failed: \(error.localizedDescription)")
                MainActor.assumeIsolated { self?.stopAdvertising() }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            Logger.ui.error("Remote pad listener did not start: \(error.localizedDescription)")
        }
    }

    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        dropPad()
    }

    // MARK: - One pad at a time

    private func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        codec = RemoteControllerCodec()
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated { self?.dropPad(if: connection) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, self.connection === connection else { return }
                if let data, !data.isEmpty {
                    for message in self.codec.decode(data) {
                        self.handle(message)
                    }
                }
                if isComplete || error != nil {
                    self.dropPad(if: connection)
                    return
                }
                self.receive(on: connection)
            }
        }
    }

    private func handle(_ message: RemoteControllerMessage) {
        switch message {
        case .hello(let padName):
            connectedPadName = padName
            onPadChanged?(padName)
        case .button(let button, let pressed):
            onButton?(button, pressed)
        }
    }

    /// Ignores a teardown from a connection that was already replaced.
    private func dropPad(if connection: NWConnection) {
        guard self.connection === connection else { return }
        dropPad()
    }

    private func dropPad() {
        connection?.cancel()
        connection = nil
        codec = RemoteControllerCodec()
        guard connectedPadName != nil else { return }
        connectedPadName = nil
        onPadChanged?(nil)
    }
}
