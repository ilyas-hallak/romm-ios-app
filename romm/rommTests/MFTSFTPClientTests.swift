//
//  MFTSFTPClientTests.swift
//  rommTests
//
//  `MFTSFTPClient` itself needs a real server, so these cover only the
//  destination-file preparation and cleanup around a download in isolation.
//

import Foundation
import Testing
@testable import romm

struct MFTSFTPClientTests {
    @Test func prepareDownloadDestinationCreatesAnEmptyFileAtAFreshPath() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        try MFTSFTPClient.prepareDownloadDestination(atPath: path)

        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)).isEmpty)
    }

    @Test func prepareDownloadDestinationTruncatesAnExistingFile() throws {
        let path = makeTempPath()
        try Data("leftover from a previous attempt".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }

        try MFTSFTPClient.prepareDownloadDestination(atPath: path)

        #expect(try Data(contentsOf: URL(fileURLWithPath: path)).isEmpty)
    }

    @Test func removePartialDownloadDeletesTheFile() throws {
        let path = makeTempPath()
        try Data().write(to: URL(fileURLWithPath: path))

        MFTSFTPClient.removePartialDownload(atPath: path)

        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    @Test func removePartialDownloadIsSafeWhenNothingExists() {
        let path = makeTempPath()

        MFTSFTPClient.removePartialDownload(atPath: path)

        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    private func makeTempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    }
}
