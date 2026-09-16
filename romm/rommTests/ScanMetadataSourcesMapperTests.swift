//
//  ScanMetadataSourcesMapperTests.swift
//  rommTests
//

import Testing
@testable import romm

struct ScanMetadataSourcesMapperTests {

    @Test func sendsOnlyTheSourcesTheServerHasConfigured() {
        let sources = ScanMetadataSourcesMapper.mapFromAPI(MetadataSourcesDict(
            ANY_SOURCE_ENABLED: true,
            IGDB_API_ENABLED: true,
            SS_API_ENABLED: true
        ))

        #expect(sources.apis == ["igdb", "ss"])
    }

    @Test func usesTheNamesTheScanPayloadExpects() {
        // The heartbeat flag and the api string differ often enough that a
        // derived mapping would be wrong, e.g. STEAMGRIDDB against sgdb.
        let sources = ScanMetadataSourcesMapper.mapFromAPI(MetadataSourcesDict(
            ANY_SOURCE_ENABLED: true,
            STEAMGRIDDB_API_ENABLED: true,
            RA_API_ENABLED: true,
            HLTB_API_ENABLED: true
        ))

        #expect(sources.apis == ["sgdb", "ra", "hltb"])
    }

    @Test func aServerWithoutAnySourceSendsAnEmptyList() {
        let sources = ScanMetadataSourcesMapper.mapFromAPI(MetadataSourcesDict())

        #expect(sources.apis.isEmpty)
        #expect(sources.playmatchEnabled == false)
    }

    @Test func playmatchRidesAlongWithIGDB() {
        let sources = ScanMetadataSourcesMapper.mapFromAPI(MetadataSourcesDict(
            ANY_SOURCE_ENABLED: true,
            IGDB_API_ENABLED: true,
            PLAYMATCH_API_ENABLED: true
        ))

        #expect(sources.playmatchEnabled)
        // Playmatch is a flag of its own, never an entry in the api list.
        #expect(sources.apis == ["igdb"])
    }

    @Test func playmatchWithoutIGDBIsNotSent() {
        // The server only honours playmatch together with IGDB, so asking for
        // it on its own would be a payload the server cannot act on.
        let sources = ScanMetadataSourcesMapper.mapFromAPI(MetadataSourcesDict(
            ANY_SOURCE_ENABLED: true,
            MOBY_API_ENABLED: true,
            PLAYMATCH_API_ENABLED: true
        ))

        #expect(sources.playmatchEnabled == false)
        #expect(sources.apis == ["moby"])
    }
}
