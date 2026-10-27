//
//  ScanRepositoryTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct ScanRepositoryTests {

    /// `startScan` always reads the heartbeat first, so every test that calls
    /// it needs one stubbed, even when the metadata sources don't matter.
    private static func heartbeat(metadataSources: MetadataSourcesDict = MetadataSourcesDict()) -> HeartbeatResponse {
        HeartbeatResponse(
            SYSTEM: SystemDict(),
            METADATA_SOURCES: metadataSources,
            FILESYSTEM: FilesystemDict(),
            EMULATION: EmulationDict(),
            FRONTEND: FrontendDict(),
            OIDC: OIDCDict()
        )
    }

    @Test func aConflictBecomesARefusalWithTheServersDetail() {
        let error = APIClientError.invalidResponse(409, #"{"detail": "A library scan is already running"}"#)

        #expect(ScanRepository.refusalMessage(for: error) == "A library scan is already running")
    }

    @Test func noWorkerBecomesARefusalWithTheServersDetail() {
        let error = APIClientError.invalidResponse(503, #"{"detail": "No scan worker is listening, so the scan cannot be queued"}"#)

        #expect(ScanRepository.refusalMessage(for: error) == "No scan worker is listening, so the scan cannot be queued")
    }

    @Test func aConflictWithoutADecodableDetailFallsBackToAGenericMessage() {
        let error = APIClientError.invalidResponse(409, "not json")

        #expect(ScanRepository.refusalMessage(for: error) == "A scan is already in progress.")
    }

    @Test func anUnrelatedStatusCodeIsNotARefusal() {
        #expect(ScanRepository.refusalMessage(for: .invalidResponse(500, "boom")) == nil)
        #expect(ScanRepository.refusalMessage(for: .authenticationRequired) == nil)
    }

    @Test func startScanQueuesAPostAndSendsEveryEnabledSource() async throws {
        let apiClient = FakeAPIClient()
        apiClient.heartbeatToReturn = Self.heartbeat(
            metadataSources: MetadataSourcesDict(ANY_SOURCE_ENABLED: true, IGDB_API_ENABLED: true, SS_API_ENABLED: true)
        )
        let repository = ScanRepository(apiClient: apiClient)

        try await repository.startScan(type: .quick, platformIds: [1, 2])

        let request = try #require(apiClient.startLibraryScanRequests.first)
        #expect(request.type == "quick")
        #expect(request.platforms == [1, 2])
        #expect(request.apis == ["igdb", "ss"])
    }

    @Test func aConflictFromStartScanThrowsARefusal() async {
        let apiClient = FakeAPIClient()
        apiClient.heartbeatToReturn = Self.heartbeat()
        apiClient.startLibraryScanError = APIClientError.invalidResponse(409, #"{"detail": "A scan is already running"}"#)
        let repository = ScanRepository(apiClient: apiClient)

        await #expect(throws: ScanStartError.refused("A scan is already running")) {
            try await repository.startScan(type: .quick, platformIds: [])
        }
    }

    @Test func anUnrelatedFailureFromStartScanPropagates() async {
        let apiClient = FakeAPIClient()
        apiClient.heartbeatToReturn = Self.heartbeat()
        apiClient.startLibraryScanError = APIClientError.invalidResponse(500, "boom")
        let repository = ScanRepository(apiClient: apiClient)

        await #expect(throws: APIClientError.self) {
            try await repository.startScan(type: .quick, platformIds: [])
        }
    }

    @Test func aForbiddenResponseMeansTheTokenIsMissingTheScope() async {
        // Same scope mismatch as on the status poll: the role allows
        // `tasks.run`, but the current sign-in's token was never granted it.
        let apiClient = FakeAPIClient()
        apiClient.heartbeatToReturn = Self.heartbeat()
        apiClient.startLibraryScanError = APIClientError.invalidResponse(403, "Forbidden")
        let repository = ScanRepository(apiClient: apiClient)

        await #expect(throws: LibraryScanAccessError.missingScope) {
            try await repository.startScan(type: .quick, platformIds: [])
        }
    }
}
