//
//  IncomingRomFileRepositoryTests.swift
//  rommTests
//
//  Exercises `stage(url:)` against real, throwaway directories on disk, since
//  its whole job is file system behavior (move vs. copy, cleanup on failure).
//

import Foundation
import Testing
@testable import romm

struct IncomingRomFileRepositoryTests {
    private struct Fixture {
        let root: URL
        let rootDirectory: URL
        let inboxDirectory: URL
        let repository: IncomingRomFileRepository
    }

    private func makeFixture() -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("incoming-rom-tests-\(UUID().uuidString)")
        let rootDirectory = root.appendingPathComponent("PendingUploads")
        let inboxDirectory = root.appendingPathComponent("Documents/Inbox")
        try? FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        let repository = IncomingRomFileRepository(rootDirectory: rootDirectory, inboxDirectory: inboxDirectory)
        return Fixture(root: root, rootDirectory: rootDirectory, inboxDirectory: inboxDirectory, repository: repository)
    }

    private func write(_ contents: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
    }

    @Test func copyingAFileFromOutsideTheInboxLeavesTheSourceInPlace() throws {
        let fixture = makeFixture()
        let source = fixture.root.appendingPathComponent("Downloads/Pokemon.gba")
        try write(Data(repeating: 0xAB, count: 10), to: source)

        let staged = try fixture.repository.stage(url: source)

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: staged.fileURL.path))
        #expect(staged.fileSize == 10)
    }

    @Test func stagingAFileFromTheInboxMovesItInsteadOfCopying() throws {
        let fixture = makeFixture()
        let source = fixture.inboxDirectory.appendingPathComponent("Pokemon.gba")
        try write(Data(repeating: 0xAB, count: 10), to: source)

        let staged = try fixture.repository.stage(url: source)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: staged.fileURL.path))
    }

    @Test func stagingAnEmptyFileThrowsAndLeavesNoJobFolder() throws {
        let fixture = makeFixture()
        let source = fixture.root.appendingPathComponent("Downloads/empty.gba")
        try write(Data(), to: source)

        #expect(throws: RomUploadError.self) {
            try fixture.repository.stage(url: source)
        }

        let remainingJobFolders = (try? FileManager.default.contentsOfDirectory(atPath: fixture.rootDirectory.path)) ?? []
        #expect(remainingJobFolders.isEmpty)
    }

    @Test func stagingAnEmptyFileFromTheInboxLeavesNoJobFolderEither() throws {
        let fixture = makeFixture()
        let source = fixture.inboxDirectory.appendingPathComponent("empty.gba")
        try write(Data(), to: source)

        #expect(throws: RomUploadError.self) {
            try fixture.repository.stage(url: source)
        }

        let remainingJobFolders = (try? FileManager.default.contentsOfDirectory(atPath: fixture.rootDirectory.path)) ?? []
        #expect(remainingJobFolders.isEmpty)
    }

    @Test func removeStagedFileDeletesTheWholeJobFolder() throws {
        let fixture = makeFixture()
        let source = fixture.root.appendingPathComponent("Downloads/Pokemon.gba")
        try write(Data(repeating: 0xAB, count: 10), to: source)
        let staged = try fixture.repository.stage(url: source)

        fixture.repository.removeStagedFile(relativePath: staged.relativePath)

        let jobFolder = staged.fileURL.deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: jobFolder.path))
    }
}
