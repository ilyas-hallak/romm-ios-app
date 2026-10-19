//
//  ScanRepositoryTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct ScanRepositoryTests {

    @Test func aConflictBecomesAFailedEventWithTheServersDetail() {
        let error = APIClientError.invalidResponse(409, #"{"detail": "A library scan is already running"}"#)

        #expect(ScanRepository.refusalEvent(for: error) == .failed("A library scan is already running"))
    }

    @Test func noWorkerBecomesAFailedEventWithTheServersDetail() {
        let error = APIClientError.invalidResponse(503, #"{"detail": "No scan worker is listening, so the scan cannot be queued"}"#)

        #expect(ScanRepository.refusalEvent(for: error) == .failed("No scan worker is listening, so the scan cannot be queued"))
    }

    @Test func aConflictWithoutADecodableDetailFallsBackToAGenericMessage() {
        let error = APIClientError.invalidResponse(409, "not json")

        #expect(ScanRepository.refusalEvent(for: error) == .failed("A scan is already in progress."))
    }

    @Test func anUnrelatedStatusCodeIsNotARefusal() {
        #expect(ScanRepository.refusalEvent(for: .invalidResponse(500, "boom")) == nil)
        #expect(ScanRepository.refusalEvent(for: .authenticationRequired) == nil)
    }
}
