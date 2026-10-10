//
//  RomUploadQueueManagerTests.swift
//  rommTests
//
//  State-transition tests for the upload queue: a fake repository stands in
//  for the network, a fake staging repository stands in for disk, and an
//  in-memory store stands in for the persisted queue file.
//

import Foundation
import Testing
@testable import romm

/// Plain in-memory stand-in for the persisted queue file.
private final class InMemoryRomUploadJobStore: PRomUploadJobStore, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [RomUploadJob] = []

    init(seed: [RomUploadJob] = []) {
        jobs = seed
    }

    func allJobs() -> [RomUploadJob] {
        lock.lock(); defer { lock.unlock() }
        return jobs
    }

    func job(id: UUID) -> RomUploadJob? {
        lock.lock(); defer { lock.unlock() }
        return jobs.first { $0.id == id }
    }

    func add(_ job: RomUploadJob) {
        lock.lock(); defer { lock.unlock() }
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
    }

    func replace(_ job: RomUploadJob) {
        lock.lock(); defer { lock.unlock() }
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
    }

    func remove(jobId: UUID) {
        lock.lock(); defer { lock.unlock() }
        jobs.removeAll { $0.id == jobId }
    }
}

private struct UploadTestError: LocalizedError {
    var errorDescription: String? { "Upload failed" }
}

/// Lets a test hold `start(...)` open until it explicitly lets it through, so
/// `cancel(id:)` can run while the call is still in flight.
private final class StartGate: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        await withCheckedContinuation { continuation in
            isWaiting = true
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
struct RomUploadQueueManagerTests {

    private struct Fixture {
        let repository: FakeRomUploadRepository
        let staging: FakeIncomingRomFileRepository
        let store: InMemoryRomUploadJobStore
        let manager: RomUploadQueueManager
    }

    private func makeFixture(seed: [RomUploadJob] = []) -> Fixture {
        let repository = FakeRomUploadRepository()
        let staging = FakeIncomingRomFileRepository()
        let store = InMemoryRomUploadJobStore(seed: seed)
        let manager = RomUploadQueueManager(repository: repository, stagingRepository: staging, store: store)
        return Fixture(repository: repository, staging: staging, store: store, manager: manager)
    }

    private func job(id: UUID = UUID(), fileName: String = "Pokemon.gba", totalChunks: Int = 1, state: RomUploadJob.State = .queued) -> RomUploadJob {
        RomUploadJob(
            id: id,
            fileName: fileName,
            fileSize: 10,
            platformId: 3,
            platformName: "Game Boy Advance",
            stagedFilePath: "\(id.uuidString)/\(fileName)",
            uploadId: nil,
            nextChunkIndex: 0,
            totalChunks: totalChunks,
            state: state
        )
    }

    /// The manager's own processing task runs detached from the test, so
    /// settle on a condition rather than sleeping.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }

    // MARK: - Enqueue / happy path

    @Test func enqueueingAFileUploadsEveryChunkAndCompletes() async throws {
        let fixture = makeFixture()
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 20))

        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { fixture.manager.jobs.first?.state == .completed }

        #expect(fixture.repository.startedUploads.map(\.fileName) == ["Pokemon.gba"])
        #expect(fixture.repository.uploadedChunkIndexes == [0])
        #expect(fixture.repository.completedUploadIds == ["upload-1"])
        #expect(fixture.staging.removedRelativePaths == [staged.relativePath])
        #expect(fixture.manager.activeCount == 0)
    }

    // MARK: - Failure

    @Test func aFailedChunkUploadMarksTheJobFailedAndKeepsTheStagedFile() async throws {
        let fixture = makeFixture()
        fixture.repository.uploadChunkError = UploadTestError()
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))

        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { if case .failed = fixture.manager.jobs.first?.state { return true } else { return false } }

        #expect(fixture.manager.jobs.first?.state == .failed("Upload failed"))
        #expect(fixture.staging.removedRelativePaths.isEmpty)
    }

    @Test func retryingAFailedJobStartsItOverAndSucceeds() async throws {
        let fixture = makeFixture()
        fixture.repository.uploadChunkError = UploadTestError()
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))
        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")
        await settle { if case .failed = fixture.manager.jobs.first?.state { return true } else { return false } }

        fixture.repository.uploadChunkError = nil
        fixture.manager.retry(id: staged.id)
        await settle { fixture.manager.jobs.first?.state == .completed }

        #expect(fixture.manager.jobs.first?.state == .completed)
    }

    @Test func aMissingStagedFileFailsWithoutCallingTheRepository() async throws {
        let fixture = makeFixture()
        let staged = StagedRomFile(
            id: UUID(),
            fileName: "gone.gba",
            fileSize: 10,
            fileURL: fixture.staging.root.appendingPathComponent("does-not-exist/gone.gba"),
            relativePath: "does-not-exist/gone.gba"
        )

        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { if case .failed = fixture.manager.jobs.first?.state { return true } else { return false } }

        #expect(fixture.repository.startedUploads.isEmpty)
    }

    // MARK: - Cancel

    @Test func cancellingAQueuedJobRemovesTheStagedFileAndMarksItCancelled() async throws {
        let fixture = makeFixture()
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))
        // Keep the job from completing before cancel runs.
        fixture.repository.uploadChunkError = UploadTestError()
        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        fixture.manager.cancel(id: staged.id)

        #expect(fixture.manager.jobs.first?.state == .cancelled)
        #expect(fixture.staging.removedRelativePaths == [staged.relativePath])
    }

    @Test func cancellingDuringAnActiveUploadStopsItWithoutResurrectingTheJob() async throws {
        let fixture = makeFixture()
        // Holds the in-flight chunk open until cancelled, standing in for a
        // slow network call that `cancel(id:)` has to interrupt rather than
        // just outrun.
        fixture.repository.chunkGate = { try await Task.sleep(for: .seconds(5)) }
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))
        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { if case .uploading = fixture.manager.jobs.first?.state { return true } else { return false } }

        fixture.manager.cancel(id: staged.id)
        await settle { fixture.manager.jobs.first?.state == .cancelled }

        // Let the cancelled task actually unwind, and make sure it does not
        // clobber the cancelled state once it does.
        for _ in 0..<20 { await Task.yield() }

        #expect(fixture.manager.jobs.first?.state == .cancelled)
        #expect(fixture.repository.uploadedChunkIndexes.isEmpty)
        #expect(fixture.repository.completedUploadIds.isEmpty)
        #expect(fixture.staging.removedRelativePaths == [staged.relativePath])
    }

    @Test func cancellingWhileStartIsInFlightCancelsTheNewUploadSession() async throws {
        let fixture = makeFixture()
        let gate = StartGate()
        fixture.repository.startGate = { await gate.wait() }
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))

        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { gate.isWaiting }
        fixture.manager.cancel(id: staged.id)
        // cancel(id:) marks the job cancelled synchronously, before start()
        // has even returned, so settle on the session actually being
        // cancelled server side rather than on job state.
        gate.open()
        await settle { !fixture.repository.cancelledUploadIds.isEmpty }

        #expect(fixture.repository.startedUploads.count == 1)
        #expect(fixture.repository.cancelledUploadIds == ["upload-1"])
    }

    @Test func aLateProgressCallbackAfterCompletionDoesNotResurrectTheJob() async throws {
        let fixture = makeFixture()
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))
        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { fixture.manager.jobs.first?.state == .completed }

        let lateHandler = try #require(fixture.repository.capturedProgressHandlers.first)
        lateHandler(0.1)
        for _ in 0..<5 { await Task.yield() }

        #expect(fixture.manager.jobs.first?.state == .completed)
    }

    // MARK: - Session expiry

    @Test func anExpiredUploadSessionRestartsOnceAndSucceeds() async throws {
        let fixture = makeFixture()
        fixture.repository.uploadChunkErrorOnce = RomUploadError.sessionExpired
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))

        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { fixture.manager.jobs.first?.state == .completed }

        #expect(fixture.repository.startedUploads.count == 2)
        #expect(fixture.manager.jobs.first?.state == .completed)
    }

    @Test func anUploadSessionThatKeepsExpiringFailsAfterOneRestartInsteadOfLoopingForever() async throws {
        let fixture = makeFixture()
        fixture.repository.uploadChunkError = RomUploadError.sessionExpired
        let staged = fixture.staging.seed(fileName: "Pokemon.gba", contents: Data(repeating: 0xAB, count: 10))

        fixture.manager.enqueue(file: staged, platformId: 3, platformName: "Game Boy Advance")

        await settle { if case .failed = fixture.manager.jobs.first?.state { return true } else { return false } }

        #expect(fixture.repository.startedUploads.count == 2)
        #expect(fixture.manager.jobs.first?.state == .failed(RomUploadError.sessionExpired.localizedDescription))
    }

    // MARK: - Remove / clear

    @Test func removingAnActiveJobDoesNothing() async throws {
        let fixture = makeFixture(seed: [job(state: .uploading(progress: 0.5))])

        fixture.manager.remove(id: fixture.store.allJobs()[0].id)

        #expect(fixture.manager.jobs.count == 1)
    }

    @Test func removingAFinishedJobDropsItFromTheQueue() async throws {
        let finishedJob = job(state: .completed)
        let fixture = makeFixture(seed: [finishedJob])

        fixture.manager.remove(id: finishedJob.id)

        #expect(fixture.manager.jobs.isEmpty)
        #expect(fixture.store.allJobs().isEmpty)
    }

    @Test func clearFinishedKeepsOnlyWhatIsStillActive() async throws {
        let active = job(fileName: "active.gba", state: .uploading(progress: 0.2))
        let done = job(fileName: "done.gba", state: .completed)
        let failed = job(fileName: "failed.gba", state: .failed("oops"))
        let fixture = makeFixture(seed: [active, done, failed])

        fixture.manager.clearFinished()

        #expect(fixture.manager.jobs.map(\.id) == [active.id])
    }

    // MARK: - Resume

    @Test func resumingPutsInterruptedJobsBackInTheQueueAndFinishesThem() async throws {
        let staged = FakeIncomingRomFileRepository()
        let interrupted = job(fileName: "mid.gba", totalChunks: 1, state: .uploading(progress: 0))
        let seededFile = staged.seed(fileName: "mid.gba", contents: Data(repeating: 0x02, count: 5))
        // Use the same id/relativePath the staged helper produced, so resolve() finds it.
        let alignedJob = RomUploadJob(
            id: interrupted.id,
            fileName: "mid.gba",
            fileSize: 5,
            platformId: 3,
            platformName: "Game Boy Advance",
            stagedFilePath: seededFile.relativePath,
            uploadId: nil,
            nextChunkIndex: 0,
            totalChunks: 1,
            state: .uploading(progress: 0)
        )
        let repository = FakeRomUploadRepository()
        let store = InMemoryRomUploadJobStore(seed: [alignedJob])
        let manager = RomUploadQueueManager(repository: repository, stagingRepository: staged, store: store)

        manager.resumeInterruptedJobs()

        await settle { manager.jobs.first?.state == .completed }

        #expect(repository.startedUploads.count == 1)
        #expect(manager.jobs.first?.state == .completed)
    }
}
