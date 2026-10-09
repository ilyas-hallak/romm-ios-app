//
//  SyncNegotiateRequestEncodingTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

/// `SyncNegotiateRequest` relies on synthesized `Encodable` (only `init` and
/// `CodingKeys` are hand-written), which already omits a nil optional via
/// `encodeIfPresent`. These pin that behavior for `rom_ids` down.
@MainActor
struct SyncNegotiateRequestEncodingTests {

    private func encode(_ request: SyncNegotiateRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @Test func omitsRomIdsWhenNil() throws {
        let request = SyncNegotiateRequest(deviceId: "device-1", saves: [])
        let json = try encode(request)
        #expect(json["rom_ids"] == nil)
    }

    @Test func includesRomIdsWhenSet() throws {
        let request = SyncNegotiateRequest(deviceId: "device-1", saves: [], romIds: [7, 9])
        let json = try encode(request)
        #expect(json["rom_ids"] as? [Int] == [7, 9])
    }
}
