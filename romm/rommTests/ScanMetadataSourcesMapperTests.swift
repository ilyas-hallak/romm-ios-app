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
    }

    @Test func playmatchRidesAlongWithIGDB() {
        // Playmatch is picked through `apis` like any other source, the server
        // just only honours it together with IGDB.
        let sources = ScanMetadataSourcesMapper.mapFromAPI(MetadataSourcesDict(
            ANY_SOURCE_ENABLED: true,
            IGDB_API_ENABLED: true,
            PLAYMATCH_API_ENABLED: true
        ))

        #expect(sources.apis == ["igdb", "playmatch"])
    }

    @Test func playmatchWithoutIGDBIsNotSent() {
        // The server only honours playmatch together with IGDB, so asking for
        // it on its own would be a payload the server cannot act on.
        let sources = ScanMetadataSourcesMapper.mapFromAPI(MetadataSourcesDict(
            ANY_SOURCE_ENABLED: true,
            MOBY_API_ENABLED: true,
            PLAYMATCH_API_ENABLED: true
        ))

        #expect(sources.apis == ["moby"])
    }
}
