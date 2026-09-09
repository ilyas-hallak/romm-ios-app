//
//  DownloadJobStore.swift
//  romm
//

import Foundation

/// The persisted download queue.
///
/// Every operation is synchronous and nonisolated. A background URLSession
/// reports progress and completion on its own delegate queue and has to resolve
/// the job file behind a task before the callback returns, so it cannot await
/// anything, and the same store is read from the main actor for the queue UI.
///
/// Nothing here throws. A queue that cannot be read has to look empty rather
/// than take the app down, and a write failure must not break a delegate
/// callback, so failures are logged by the implementation.
nonisolated protocol PDownloadJobStore {
    /// Every job, in the order it was added.
    func allJobs() -> [DownloadJob]

    func job(id: UUID) -> DownloadJob?

    /// The job for a ROM, used to answer whether a ROM is already queued.
    func job(romId: Int) -> DownloadJob?

    /// Appends a job. A job with the same id is replaced, so a retried add
    /// cannot put the same download in the queue twice.
    func add(_ job: DownloadJob)

    /// Replaces a job wholesale, matched by id. No-op for an unknown id, which
    /// is the normal outcome when a job was cancelled while a callback for it
    /// was still on its way.
    func replace(_ job: DownloadJob)

    /// Mutates one file of a job in place, matched by file name. Read, modify
    /// and write happen under one lock, so a progress checkpoint coming from
    /// the delegate queue cannot undo a state change made on the main actor.
    func updateFile(jobId: UUID, fileName: String, _ mutate: (inout DownloadJobFile) -> Void)

    func remove(jobId: UUID)
}

/// File backed download queue, one JSON document under Application Support.
///
/// Not an actor on purpose: the URLSession delegate callbacks that drive the
/// queue are synchronous and need their job file before they return, and an
/// actor would put an await in front of every one of them. A lock serialises
/// the file instead, so main actor reads and delegate queue writes cannot
/// interleave inside a read, modify, write cycle.
nonisolated final class DownloadJobStore: PDownloadJobStore {

    static let queueFileName = "download-queue.json"

    private let queueFileURL: URL
    private let fileManager = FileManager.default
    /// Guards the whole read, modify, write cycle, not just the file write.
    private let lock = NSLock()

    init(rootDirectory: URL) {
        self.queueFileURL = rootDirectory.appendingPathComponent(Self.queueFileName)
        // Application Support is not guaranteed to exist on a fresh install.
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    convenience init() {
        self.init(rootDirectory: DownloadJobStore.defaultRootDirectory())
    }

    /// Application Support, not Documents: the queue is the app's own
    /// bookkeeping and has no business showing up next to the ROMs in Files.
    static func defaultRootDirectory() -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport ?? fileManager.temporaryDirectory
    }

    // MARK: - Reads

    func allJobs() -> [DownloadJob] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    func job(id: UUID) -> DownloadJob? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().first { $0.id == id }
    }

    func job(romId: Int) -> DownloadJob? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().first { $0.romId == romId }
    }

    // MARK: - Writes

    func add(_ job: DownloadJob) {
        lock.lock()
        defer { lock.unlock() }
        var jobs = loadLocked()
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
        saveLocked(jobs)
    }

    func replace(_ job: DownloadJob) {
        lock.lock()
        defer { lock.unlock() }
        var jobs = loadLocked()
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        saveLocked(jobs)
    }

    func updateFile(jobId: UUID, fileName: String, _ mutate: (inout DownloadJobFile) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var jobs = loadLocked()
        guard let jobIndex = jobs.firstIndex(where: { $0.id == jobId }),
              let fileIndex = jobs[jobIndex].files.firstIndex(where: { $0.fileName == fileName }) else {
            return
        }
        mutate(&jobs[jobIndex].files[fileIndex])
        saveLocked(jobs)
    }

    func remove(jobId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var jobs = loadLocked()
        let countBefore = jobs.count
        jobs.removeAll { $0.id == jobId }
        guard jobs.count != countBefore else { return }
        saveLocked(jobs)
    }

    // MARK: - File access

    /// Defensive by contract: a missing file is an empty queue, and a file that
    /// cannot be decoded is reported and then treated as an empty queue. The
    /// alternative, throwing, would run at app start and take the app with it.
    private func loadLocked() -> [DownloadJob] {
        guard let data = try? Data(contentsOf: queueFileURL) else { return [] }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([DownloadJob].self, from: data)
        } catch {
            log("Download queue could not be decoded, continuing with an empty queue: \(error.localizedDescription)")
            return []
        }
    }

    /// Written atomically, so a crash part way through leaves the previous
    /// queue in place instead of a truncated file that would drop every job.
    /// `.atomic` writes an auxiliary file and swaps it in.
    ///
    /// Dates keep `Date`'s own coding instead of being reformatted as ISO 8601:
    /// this file is the app's own state, and a reformatted date would come back
    /// with less precision than it went in with.
    private func saveLocked(_ jobs: [DownloadJob]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(jobs)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            log("Download queue could not be written: \(error.localizedDescription)")
        }
    }

    /// `Logger` is main actor bound while this store is also used from the
    /// URLSession delegate queue, so the line is handed to the main actor
    /// rather than logged from wherever the caller happens to be.
    private func log(_ message: String) {
        Task { @MainActor in
            Logger.data.warning(message)
        }
    }
}
