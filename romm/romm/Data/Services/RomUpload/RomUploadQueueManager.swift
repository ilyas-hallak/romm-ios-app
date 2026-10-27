//
//  RomUploadQueueManager.swift
//  romm
//
//  Drives the chunked ROM upload queue, one job at a time. Unlike downloads
//  this does not run on a true background URLSession: a chunk upload is a
//  short, foreground-initiated request, and the whole job is wrapped in a
//  `UIApplication` background task so a brief backgrounding (switching apps,
//  the screen locking) does not kill it mid-chunk.
//

import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class RomUploadQueueManager {
    static let shared = RomUploadQueueManager(
        repository: DefaultDependencyFactory.shared.romUploadRepository,
        stagingRepository: DefaultDependencyFactory.shared.incomingRomFileRepository
    )

    private(set) var jobs: [RomUploadJob]

    @ObservationIgnored private let repository: PRomUploadRepository
    @ObservationIgnored private let stagingRepository: PIncomingRomFileRepository
    @ObservationIgnored private let store: PRomUploadJobStore
    @ObservationIgnored private let logger = Logger.data
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    /// The job `processQueue` is currently awaiting, and the task running it,
    /// so `cancel(id:)` can stop that one upload in place instead of only
    /// marking it cancelled and letting it run to completion underneath.
    @ObservationIgnored private var activeJobId: UUID?
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    init(
        repository: PRomUploadRepository,
        stagingRepository: PIncomingRomFileRepository,
        store: PRomUploadJobStore = RomUploadJobStore()
    ) {
        self.repository = repository
        self.stagingRepository = stagingRepository
        self.store = store
        self.jobs = store.allJobs()
    }

    // MARK: - Derived state

    var activeCount: Int {
        jobs.filter(\.state.isActive).count
    }

    // MARK: - Queue operations

    func enqueue(file: StagedRomFile, platformId: Int, platformName: String) {
        let totalChunks = RomUploadChunkPlan.totalChunks(fileSize: file.fileSize)
        let job = RomUploadJob(
            id: file.id,
            fileName: file.fileName,
            fileSize: file.fileSize,
            platformId: platformId,
            platformName: platformName,
            stagedFilePath: file.relativePath,
            uploadId: nil,
            nextChunkIndex: 0,
            totalChunks: totalChunks,
            state: .queued
        )
        jobs.append(job)
        store.add(job)
        kickProcessing()
    }

    func cancel(id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if id == activeJobId {
            activeTask?.cancel()
        }
        if let uploadId = job.uploadId {
            Task { try? await repository.cancel(uploadId: uploadId) }
        }
        cleanUpStagedFile(for: job)
        update(id: id) { $0.state = .cancelled }
    }

    func retry(id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), case .failed = job.state else { return }
        update(id: id) { $0.state = .queued }
        kickProcessing()
    }

    func remove(id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard !job.state.isActive else { return }
        cleanUpStagedFile(for: job)
        jobs.removeAll { $0.id == id }
        store.remove(jobId: id)
    }

    func clearFinished() {
        let finished = jobs.filter { !$0.state.isActive }
        for job in finished {
            // No-op for completed/cancelled jobs, which already cleaned up
            // their staged copy; a failed job still has one, and it can be a
            // multi-gigabyte file left behind otherwise.
            cleanUpStagedFile(for: job)
            jobs.removeAll { $0.id == job.id }
            store.remove(jobId: job.id)
        }
    }

    /// Puts a job interrupted by the app being killed mid-upload back in the
    /// queue (it keeps `nextChunkIndex`, so the resend picks up where it left
    /// off), then kicks the processing loop. Called once at app start.
    func resumeInterruptedJobs() {
        for job in jobs where job.state.isActive {
            update(id: job.id) { $0.state = .queued }
        }
        kickProcessing()
    }

    // MARK: - Processing

    private func kickProcessing() {
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            await self?.processQueue()
            self?.processingTask = nil
        }
    }

    private func processQueue() async {
        beginBackgroundTask()
        defer { endBackgroundTask() }

        while let job = jobs.first(where: { if case .queued = $0.state { return true } else { return false } }) {
            activeJobId = job.id
            let task = Task { await self.run(job) }
            activeTask = task
            await task.value
            activeTask = nil
            activeJobId = nil
        }
    }

    /// Drives one job through start, every chunk, and complete. `isRestart`
    /// guards the one-shot retry when the server no longer recognizes the
    /// upload session (TTL expiry, cache flush): it is set when this call is
    /// itself that retry, so a session that keeps expiring fails outright
    /// instead of looping forever.
    private func run(_ job: RomUploadJob, isRestart: Bool = false) async {
        let fileURL = stagingRepository.resolve(relativePath: job.stagedFilePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            update(id: job.id) { $0.state = .failed("The file is no longer available.") }
            return
        }

        do {
            var uploadId = job.uploadId
            if uploadId == nil {
                uploadId = try await repository.start(
                    platformId: job.platformId,
                    fileName: job.fileName,
                    fileSize: job.fileSize,
                    totalChunks: job.totalChunks
                )
                if isCancelled(job.id) {
                    // The session was created after cancel(id:) already ran,
                    // so nothing else will ever clean it up server side.
                    if let newUploadId = uploadId {
                        try? await repository.cancel(uploadId: newUploadId)
                    }
                    return markCancelledIfNeeded(job.id)
                }
                update(id: job.id) { $0.uploadId = uploadId }
            }
            guard let uploadId else { throw RomUploadError.other("No upload id") }

            update(id: job.id) { $0.state = .uploading(progress: progress(for: job)) }

            var index = job.nextChunkIndex
            while index < job.totalChunks {
                if isCancelled(job.id) { return markCancelledIfNeeded(job.id) }

                let chunkURL = try await Self.makeChunkFile(fileURL: fileURL, index: index, fileSize: job.fileSize)
                defer { try? FileManager.default.removeItem(at: chunkURL) }

                let chunkIndex = index
                try await repository.uploadChunk(uploadId: uploadId, index: chunkIndex, fileURL: chunkURL) { [weak self] chunkProgress in
                    Task { @MainActor in
                        self?.applyProgress(jobId: job.id, index: chunkIndex, chunkProgress: chunkProgress, totalChunks: job.totalChunks)
                    }
                }

                if isCancelled(job.id) { return markCancelledIfNeeded(job.id) }

                index += 1
                update(id: job.id) {
                    $0.nextChunkIndex = index
                    $0.state = .uploading(progress: Double(index) / Double(job.totalChunks))
                }
            }

            if isCancelled(job.id) { return markCancelledIfNeeded(job.id) }

            update(id: job.id) { $0.state = .finishing }
            try await repository.complete(uploadId: uploadId)

            cleanUpStagedFile(for: job)
            update(id: job.id) { $0.state = .completed }
        } catch {
            if isCancellation(error) || isCancelled(job.id) {
                markCancelledIfNeeded(job.id)
                return
            }
            if case RomUploadError.sessionExpired = error, !isRestart {
                update(id: job.id) {
                    $0.uploadId = nil
                    $0.nextChunkIndex = 0
                }
                if let resetJob = jobs.first(where: { $0.id == job.id }) {
                    await run(resetJob, isRestart: true)
                }
                return
            }
            if let romError = error as? RomUploadError {
                update(id: job.id) { $0.state = .failed(romError.localizedDescription) }
                return
            }
            logger.error("ROM upload \(job.id) failed: \(error.localizedDescription)")
            update(id: job.id) { $0.state = .failed(error.localizedDescription) }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// True once `cancel(id:)` has marked the job cancelled, or the task
    /// running it has been told to stop. Checked between every await point in
    /// `run(_:)` so a cancellation lands as soon as possible instead of only
    /// once the current network call throws.
    private func isCancelled(_ id: UUID) -> Bool {
        Task.isCancelled || jobs.first(where: { $0.id == id })?.state == .cancelled
    }

    private func markCancelledIfNeeded(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.state != .cancelled else { return }
        update(id: id) { $0.state = .cancelled }
    }

    private func progress(for job: RomUploadJob) -> Double {
        guard job.totalChunks > 0 else { return 0 }
        return Double(job.nextChunkIndex) / Double(job.totalChunks)
    }

    /// Reads one chunk's byte range into its own small temp file, since
    /// `uploadTask(with:fromFile:)` needs a file URL rather than an in-memory
    /// body for a transfer this size. `nonisolated` and `@concurrent` so this
    /// disk I/O, run once per chunk, never blocks the main actor.
    @concurrent
    nonisolated private static func makeChunkFile(fileURL: URL, index: Int, fileSize: Int64) async throws -> URL {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let range = RomUploadChunkPlan.range(forChunk: index, fileSize: fileSize)
        try handle.seek(toOffset: UInt64(range.lowerBound))
        let length = Int(range.upperBound - range.lowerBound)
        let chunkData = try handle.read(upToCount: length) ?? Data()

        let chunkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rom-upload-chunk-\(UUID().uuidString)")
        try chunkData.write(to: chunkURL)
        return chunkURL
    }

    private func cleanUpStagedFile(for job: RomUploadJob) {
        stagingRepository.removeStagedFile(relativePath: job.stagedFilePath)
    }

    private func update(id: UUID, _ mutate: (inout RomUploadJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&jobs[index])
        store.replace(jobs[index])
    }

    /// A mid-chunk progress tick: applied only while the job is still
    /// `.uploading`, and only if it is not behind what is already shown, so a
    /// callback that lands late (after the job finished, failed, or was
    /// cancelled) cannot resurrect it. Not persisted to the store, since
    /// `nextChunkIndex` already covers what a relaunch needs to resume from
    /// and a write per tick would hammer disk for no benefit.
    private func applyProgress(jobId: UUID, index: Int, chunkProgress: Double, totalChunks: Int) {
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobId }),
              case .uploading(let currentProgress) = jobs[jobIndex].state,
              totalChunks > 0 else { return }
        let completed = (Double(index) + chunkProgress) / Double(totalChunks)
        guard completed > currentProgress else { return }
        jobs[jobIndex].state = .uploading(progress: completed)
    }

    // MARK: - Background task

    private func beginBackgroundTask() {
        guard backgroundTaskId == .invalid else { return }
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "RomUpload") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
    }
}
