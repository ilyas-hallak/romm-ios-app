//
//  IncomingURLRouterTests.swift
//  rommTests
//
//  The staging chain runs detached, so file-URL tests settle on the injected
//  `IncomingRomFileState` rather than sleeping, the same way
//  `RomUploadQueueManagerTests` settles on job state.
//

import Foundation
import Testing
@testable import romm

@MainActor
struct IncomingURLRouterTests {
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func makeRouter(staging: FakeIncomingRomFileRepository, state: IncomingRomFileState) -> IncomingURLRouter {
        IncomingURLRouter(
            makeStageIncomingRomUseCase: { StageIncomingRomUseCase(repository: staging) },
            incomingFileState: state
        )
    }

    @Test func aFileURLIsStagedAndLandsInTheIncomingFileState() async throws {
        let staging = FakeIncomingRomFileRepository()
        let state = IncomingRomFileState()
        let router = makeRouter(staging: staging, state: state)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("Pokemon-\(UUID().uuidString).gba")
        try Data(repeating: 0xAB, count: 10).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        router.handle(source)
        await settle { state.pendingFile != nil }

        #expect(state.pendingFile?.fileName == source.lastPathComponent)
    }

    /// Mirrors a file the `fileImporter` sheet behind "Add ROM" hands over:
    /// not inside any Inbox, so staging has to copy rather than move it.
    @Test func aFileOutsideAnyInboxLikeTheFileImporterProvidesIsStagedToo() async throws {
        let staging = FakeIncomingRomFileRepository()
        let state = IncomingRomFileState()
        let router = makeRouter(staging: staging, state: state)
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Picker-\(UUID().uuidString)")
        let source = sourceDirectory.appendingPathComponent("SuperMario.sfc")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 5).write(to: source)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }

        router.handle(source)
        await settle { state.pendingFile != nil }

        #expect(state.pendingFile?.fileName == "SuperMario.sfc")
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func aStagingFailureLeavesTheStateUntouched() async throws {
        let staging = FakeIncomingRomFileRepository()
        staging.stageError = RomUploadError.emptyFile
        let state = IncomingRomFileState()
        let router = makeRouter(staging: staging, state: state)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString).gba")
        try Data().write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        router.handle(source)
        for _ in 0..<50 { await Task.yield() }

        #expect(state.pendingFile == nil)
    }

    @Test func aPairingDeepLinkPostsItsCode() throws {
        let staging = FakeIncomingRomFileRepository()
        let state = IncomingRomFileState()
        let router = makeRouter(staging: staging, state: state)
        var receivedCode: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .clientTokenPairingCode, object: nil, queue: nil
        ) { notification in
            receivedCode = notification.userInfo?["code"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        router.handle(URL(string: "romm://pair?code=ABCD1234")!)

        #expect(receivedCode == "ABCD1234")
        #expect(state.pendingFile == nil)
    }

    @Test func anUnknownSchemeDoesNothing() throws {
        let staging = FakeIncomingRomFileRepository()
        let state = IncomingRomFileState()
        let router = makeRouter(staging: staging, state: state)

        router.handle(URL(string: "https://example.org")!)

        #expect(state.pendingFile == nil)
    }

    @Test func anUnknownHostDoesNothing() throws {
        let staging = FakeIncomingRomFileRepository()
        let state = IncomingRomFileState()
        let router = makeRouter(staging: staging, state: state)

        router.handle(URL(string: "romm://unknown")!)

        #expect(state.pendingFile == nil)
    }
}
