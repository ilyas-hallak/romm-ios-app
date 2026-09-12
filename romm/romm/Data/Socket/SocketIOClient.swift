//
//  SocketIOClient.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//
//  A minimal Engine.IO v4 / Socket.IO client on top of URLSessionWebSocketTask.
//  Transport only, it knows nothing about RomM: the caller brings the handshake
//  URL, the session cookie and the event names.
//
//  Frame grammar (all text frames, the numeric prefix is ASCII at the start of
//  the same frame as the JSON, there is no separator):
//    0{...}   engine open
//    40       connect the default namespace, the client has to send this
//    40{...}  the server acknowledged the namespace, only now may events flow
//    42[...]  an event, ["<name>", <payload>]
//    2 / 3    engine ping / pong
//    41 / 1   namespace disconnect / engine close
//

import Foundation

/// One decoded Socket.IO event. The payload is handed over as raw JSON so
/// callers decode it with Codable instead of poking at dictionaries.
struct SocketIOEvent: Sendable {
    let name: String
    let data: Data?
}

enum SocketIOError: LocalizedError, Equatable {
    case connectTimeout
    case notConnected
    case connectRejected(String)
    case transportFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectTimeout:
            return "The server did not accept the connection in time."
        case .notConnected:
            return "The connection to the server is not open."
        case .connectRejected(let reason):
            return reason.isEmpty ? "The server rejected the connection." : reason
        case .transportFailed(let reason):
            return reason
        }
    }
}

actor SocketIOClient {
    private let handshakeURL: URL
    private let cookie: String
    private let origin: String?
    private let connectTimeout: TimeInterval
    private let session: URLSession

    private let stream: AsyncStream<SocketIOEvent>
    private let continuation: AsyncStream<SocketIOEvent>.Continuation

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var isNamespaceConnected = false
    private var isClosed = false
    private var didFinishStream = false

    /// Every incoming event, heartbeats already answered and filtered out.
    var events: AsyncStream<SocketIOEvent> { stream }

    /// True between the namespace acknowledgement and the teardown.
    var isConnected: Bool { isNamespaceConnected && !isClosed }

    /// - Parameters:
    ///   - serverURL: The full handshake URL, including `?EIO=4&transport=websocket`.
    ///   - cookie: Value for the `Cookie` header, e.g. `name=value`.
    ///   - origin: Sent as `Origin`, some reverse proxies reject the upgrade
    ///     without it. Derived from `serverURL` when omitted.
    ///   - sessionDelegate: Lets the caller keep its own TLS handling, e.g. for
    ///     servers on a private network with a self-signed certificate.
    init(
        serverURL: URL,
        cookie: String,
        origin: String? = nil,
        connectTimeout: TimeInterval = 20,
        sessionDelegate: URLSessionDelegate? = nil
    ) {
        self.handshakeURL = serverURL
        self.cookie = cookie
        self.origin = origin ?? Self.origin(for: serverURL)
        self.connectTimeout = connectTimeout

        let configuration = URLSessionConfiguration.default
        // A web socket task treats the request timeout as an idle timeout, and
        // the server only speaks every 25 seconds (its ping interval), so this
        // has to stay well above that. The resource timeout has to outlive a
        // full scan, which can run for hours.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: nil)

        let (stream, continuation) = AsyncStream<SocketIOEvent>.makeStream(bufferingPolicy: .unbounded)
        self.stream = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    // MARK: - Connect

    /// Opens the socket and returns once the server acknowledged the default
    /// namespace with `40…`. Throws on timeout, rejection or transport failure.
    /// A client is single use: after `disconnect()` it stays closed.
    func connect() async throws {
        guard !isClosed else { throw SocketIOError.notConnected }
        guard webSocketTask == nil else { return }

        var request = URLRequest(url: handshakeURL)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        request.timeoutInterval = connectTimeout

        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()

        // No suspension point between here and installing the continuation, so
        // the receive loop cannot deliver the namespace acknowledgement before
        // there is something to resume.
        startReceiveLoop(on: task)
        startConnectTimeout()

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connectContinuation = continuation
            }
        } catch {
            disconnect()
            throw error
        }
    }

    // MARK: - Emit

    /// Writes a `42["<event>", <payload>]` frame. Only valid once `connect()`
    /// has returned.
    func emit(_ event: String, _ payload: [String: any Sendable]? = nil) async throws {
        guard !isClosed, isNamespaceConnected, let webSocketTask else {
            throw SocketIOError.notConnected
        }

        var packet: [Any] = [event]
        if let payload {
            packet.append(payload)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: packet),
              let json = String(data: data, encoding: .utf8) else {
            throw SocketIOError.transportFailed("The event payload could not be encoded.")
        }

        do {
            try await webSocketTask.send(.string("42\(json)"))
        } catch {
            throw SocketIOError.transportFailed(error.localizedDescription)
        }
    }

    // MARK: - Disconnect

    /// Cancels the socket and finishes the event stream. Safe to call twice.
    func disconnect() {
        guard !isClosed else { return }
        isClosed = true
        isNamespaceConnected = false

        timeoutTask?.cancel()
        timeoutTask = nil

        let task = webSocketTask
        webSocketTask = nil
        task?.cancel(with: .goingAway, reason: nil)

        resumeConnect(with: .failure(SocketIOError.notConnected))

        receiveTask?.cancel()
        receiveTask = nil

        session.invalidateAndCancel()
        finishStream()
    }

    // MARK: - Receiving

    private func startReceiveLoop(on task: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    // receive() delivers exactly one message, so it has to be
                    // re-armed after every one or the stream would stop after
                    // the first event.
                    let message = try await task.receive()
                    guard let self else { return }
                    await self.handle(message: message)
                } catch {
                    guard let self else { return }
                    await self.handleTransportFailure(error)
                    return
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
        let frame: String?
        switch message {
        case .string(let text):
            frame = text
        case .data(let data):
            frame = String(data: data, encoding: .utf8)
        @unknown default:
            frame = nil
        }

        guard let frame, !frame.isEmpty else { return }
        await handle(frame: frame)
    }

    private func handle(frame: String) async {
        // Heartbeats never reach the caller.
        if frame == "2" {
            await sendRaw("3")
            return
        }
        if frame == "3" { return }

        guard let type = frame.first else { return }
        let body = String(frame.dropFirst())

        switch type {
        case "0":
            // Engine open. The namespace has to be connected explicitly before
            // anything may be emitted.
            await sendRaw("40")
        case "1":
            // Engine close.
            disconnect()
        case "4":
            handleSocketIOPacket(body)
        default:
            break
        }
    }

    /// `body` is the Socket.IO packet, i.e. the frame without its leading `4`.
    /// Only the default namespace is used here, so a namespace prefix is not
    /// expected and is ignored along with the rest of the packet.
    private func handleSocketIOPacket(_ body: String) {
        guard let type = body.first else { return }
        let payload = String(body.dropFirst())

        switch type {
        case "0":
            isNamespaceConnected = true
            resumeConnect(with: .success(()))
        case "1":
            disconnect()
        case "2":
            if let event = Self.decodeEvent(payload) {
                continuation.yield(event)
            }
        case "4":
            resumeConnect(with: .failure(SocketIOError.connectRejected(Self.rejectionReason(payload))))
            disconnect()
        default:
            break
        }
    }

    private func sendRaw(_ frame: String) async {
        guard !isClosed, let webSocketTask else { return }
        do {
            try await webSocketTask.send(.string(frame))
        } catch {
            handleTransportFailure(error)
        }
    }

    private func handleTransportFailure(_ error: Error) {
        guard !isClosed else { return }
        resumeConnect(with: .failure(SocketIOError.transportFailed(error.localizedDescription)))
        disconnect()
    }

    // MARK: - Connect handshake bookkeeping

    private func startConnectTimeout() {
        timeoutTask = Task { [weak self, connectTimeout] in
            try? await Task.sleep(for: .seconds(connectTimeout))
            guard !Task.isCancelled else { return }
            await self?.resumeConnect(with: .failure(SocketIOError.connectTimeout))
        }
    }

    /// Resumes the waiting `connect()` exactly once, whichever path gets here
    /// first: acknowledgement, rejection, timeout, transport failure, teardown.
    private func resumeConnect(with result: Result<Void, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil

        guard let continuation = connectContinuation else { return }
        connectContinuation = nil
        continuation.resume(with: result)
    }

    private func finishStream() {
        guard !didFinishStream else { return }
        didFinishStream = true
        continuation.finish()
    }

    // MARK: - Parsing helpers

    private static func decodeEvent(_ payload: String) -> SocketIOEvent? {
        // An acknowledgement id may sit between the packet type and the array.
        guard let arrayStart = payload.firstIndex(of: "[") else { return nil }
        let json = String(payload[arrayStart...])

        guard let data = json.data(using: .utf8),
              let packet = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any],
              let name = packet.first as? String else {
            return nil
        }
        guard packet.count > 1 else {
            return SocketIOEvent(name: name, data: nil)
        }

        let encoded = try? JSONSerialization.data(withJSONObject: packet[1], options: [.fragmentsAllowed])
        return SocketIOEvent(name: name, data: encoded)
    }

    /// A connect error carries either a bare string or `{"message": "…"}`.
    private static func rejectionReason(_ payload: String) -> String {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return payload
        }
        if let message = (object as? [String: Any])?["message"] as? String { return message }
        if let message = object as? String { return message }
        return payload
    }

    private static func origin(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return nil
        }
        let scheme = components.scheme?.lowercased() == "wss" ? "https" : "http"
        guard let port = components.port else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }
}
