//
//  SocketIOFrame.swift
//  romm
//
//  Created by Ilyas Hallak on 13.09.26.
//
//  The Engine.IO v4 / Socket.IO frame grammar, kept apart from the socket that
//  acts on it. All frames are text, the numeric prefix is ASCII at the start of
//  the same frame as the JSON, there is no separator:
//    0{...}   engine open
//    2 / 3    engine ping / pong
//    1        engine close
//    40       the server acknowledged the default namespace
//    41       namespace disconnect
//    42[...]  an event, ["<name>", <payload>]
//    44{...}  the server refused the connection
//

import Foundation

/// One incoming frame, read as what the client has to do about it. Anything
/// the app does not act on reads as `.unknown` rather than failing.
nonisolated enum SocketIOFrame: Equatable {
    case engineOpen
    case engineClose
    case enginePing
    case enginePong
    case namespaceConnected
    case namespaceDisconnected
    case event(SocketIOEvent)
    case connectRejected(String)
    case unknown

    init(text: String) {
        // A heartbeat is the bare digit. A frame that starts with the same
        // digit but carries a body is something else entirely.
        if text == "2" { self = .enginePing; return }
        if text == "3" { self = .enginePong; return }

        guard let type = text.first else { self = .unknown; return }
        let body = String(text.dropFirst())

        switch type {
        case "0": self = .engineOpen
        case "1": self = .engineClose
        case "4": self = Self.socketIOPacket(body)
        default: self = .unknown
        }
    }

    /// `body` is the Socket.IO packet, i.e. the frame without its leading `4`.
    /// Only the default namespace is used, so a namespace prefix is ignored
    /// along with the rest of the packet.
    private static func socketIOPacket(_ body: String) -> SocketIOFrame {
        guard let type = body.first else { return .unknown }
        let payload = String(body.dropFirst())

        switch type {
        case "0": return .namespaceConnected
        case "1": return .namespaceDisconnected
        case "2": return decodeEvent(payload).map { .event($0) } ?? .unknown
        case "4": return .connectRejected(rejectionReason(payload))
        default: return .unknown
        }
    }

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
}
