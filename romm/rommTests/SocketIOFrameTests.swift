//
//  SocketIOFrameTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct SocketIOFrameTests {

    // MARK: - Engine.IO

    @Test func readsTheBareDigitsAsHeartbeats() {
        #expect(SocketIOFrame(text: "2") == .enginePing)
        #expect(SocketIOFrame(text: "3") == .enginePong)
    }

    @Test func aDigitWithABodyIsNotAHeartbeat() {
        // "2probe" belongs to the polling upgrade, which this client never does.
        #expect(SocketIOFrame(text: "2probe") == .unknown)
    }

    @Test func readsTheEngineOpenHandshake() {
        let frame = SocketIOFrame(text: #"0{"sid":"abc","pingInterval":25000,"pingTimeout":20000}"#)
        #expect(frame == .engineOpen)
    }

    @Test func readsTheEngineClose() {
        #expect(SocketIOFrame(text: "1") == .engineClose)
    }

    @Test func anEmptyFrameIsUnknown() {
        #expect(SocketIOFrame(text: "") == .unknown)
    }

    // MARK: - Namespace

    @Test func readsTheNamespaceAcknowledgement() {
        #expect(SocketIOFrame(text: #"40{"sid":"xyz"}"#) == .namespaceConnected)
        #expect(SocketIOFrame(text: "40") == .namespaceConnected)
    }

    @Test func readsTheNamespaceDisconnect() {
        #expect(SocketIOFrame(text: "41") == .namespaceDisconnected)
    }

    // MARK: - Events

    @Test func readsAnEventWithItsPayload() throws {
        let frame = SocketIOFrame(text: #"42["scan:scanning_rom",{"id":7,"name":"Sonic"}]"#)

        guard case .event(let event) = frame else {
            Issue.record("Expected an event, got \(frame)")
            return
        }
        #expect(event.name == "scan:scanning_rom")

        let payload = try #require(event.data)
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        #expect(object?["id"] as? Int == 7)
        #expect(object?["name"] as? String == "Sonic")
    }

    @Test func anEventWithoutAPayloadCarriesNoData() {
        let frame = SocketIOFrame(text: #"42["scan:done"]"#)

        guard case .event(let event) = frame else {
            Issue.record("Expected an event, got \(frame)")
            return
        }
        #expect(event.name == "scan:done")
        #expect(event.data == nil)
    }

    @Test func skipsAnAcknowledgementIdBetweenTheTypeAndTheArray() {
        let frame = SocketIOFrame(text: #"4212["scan:done"]"#)

        guard case .event(let event) = frame else {
            Issue.record("Expected an event, got \(frame)")
            return
        }
        #expect(event.name == "scan:done")
    }

    @Test func anEventWithAStringPayloadKeepsItAsJSON() throws {
        let frame = SocketIOFrame(text: #"42["scan:done_ko","A scan is already in progress"]"#)

        guard case .event(let event) = frame else {
            Issue.record("Expected an event, got \(frame)")
            return
        }
        let payload = try #require(event.data)
        #expect(try JSONDecoder().decode(String.self, from: payload) == "A scan is already in progress")
    }

    @Test func anEventThatIsNotAnArrayIsUnknown() {
        #expect(SocketIOFrame(text: #"42{"name":"scan:done"}"#) == .unknown)
        #expect(SocketIOFrame(text: "42[") == .unknown)
        #expect(SocketIOFrame(text: "42[42]") == .unknown)
    }

    // MARK: - Rejection

    @Test func readsTheMessageOutOfAConnectError() {
        let frame = SocketIOFrame(text: #"44{"message":"Not authorized"}"#)
        #expect(frame == .connectRejected("Not authorized"))
    }

    @Test func readsABareStringConnectError() {
        #expect(SocketIOFrame(text: #"44"Not authorized""#) == .connectRejected("Not authorized"))
    }

    @Test func keepsAnUnreadableConnectErrorAsItCame() {
        #expect(SocketIOFrame(text: "44not json at all") == .connectRejected("not json at all"))
    }

    // MARK: - Anything else

    @Test func packetTypesTheAppDoesNotActOnAreUnknown() {
        // Binary event, acknowledgement, and a type the protocol has no meaning
        // for. None of them may be mistaken for something the client acts on.
        #expect(SocketIOFrame(text: "45") == .unknown)
        #expect(SocketIOFrame(text: #"43[{"ok":true}]"#) == .unknown)
        #expect(SocketIOFrame(text: "9") == .unknown)
        #expect(SocketIOFrame(text: "4") == .unknown)
    }
}
