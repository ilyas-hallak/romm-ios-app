//
//  RomUploadChunkPlanTests.swift
//  rommTests
//

import Testing
@testable import romm

struct RomUploadChunkPlanTests {

    @Test func emptyFileHasNoChunks() {
        #expect(RomUploadChunkPlan.totalChunks(fileSize: 0) == 0)
    }

    @Test func aFileSmallerThanOneChunkStillTakesOneChunk() {
        #expect(RomUploadChunkPlan.totalChunks(fileSize: 10, chunkSize: 100) == 1)
    }

    @Test func aFileThatIsExactlyOneChunkTakesOneChunk() {
        #expect(RomUploadChunkPlan.totalChunks(fileSize: 100, chunkSize: 100) == 1)
    }

    @Test func aFileOneByteOverAChunkTakesAnExtraChunk() {
        #expect(RomUploadChunkPlan.totalChunks(fileSize: 101, chunkSize: 100) == 2)
    }

    @Test func rangesCoverTheWholeFileWithoutGapsOrOverlap() {
        let fileSize: Int64 = 250
        let chunkSize: Int64 = 100

        #expect(RomUploadChunkPlan.range(forChunk: 0, fileSize: fileSize, chunkSize: chunkSize) == 0..<100)
        #expect(RomUploadChunkPlan.range(forChunk: 1, fileSize: fileSize, chunkSize: chunkSize) == 100..<200)
        #expect(RomUploadChunkPlan.range(forChunk: 2, fileSize: fileSize, chunkSize: chunkSize) == 200..<250)
    }

    @Test func theDefaultChunkSizeStaysWellUnderTheServersSixtyFourMebibyteLimit() {
        let sixtyFourMebibytes: Int64 = 64 * 1024 * 1024
        #expect(RomUploadChunkPlan.defaultChunkSize < sixtyFourMebibytes)
    }
}
