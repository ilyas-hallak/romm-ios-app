//
//  RomUploadJobStore.swift
//  romm
//

import Foundation

/// The persisted upload queue, same shape as `PDownloadJobStore`: synchronous,
/// nonisolated, and never throws, so a progress callback or a read from the
/// main actor cannot be blocked or broken by a disk failure.
nonisolated protocol PRomUploadJobStore {
    func allJobs() -> [RomUploadJob]
    func job(id: UUID) -> RomUploadJob?

    /// Appends a job. A job with the same id is replaced.
    func add(_ job: RomUploadJob)

    /// Replaces a job wholesale, matched by id. No-op for an unknown id.
    func replace(_ job: RomUploadJob)

    func remove(jobId: UUID)
}

/// File backed upload queue, one JSON document under Application Support.
nonisolated final class RomUploadJobStore: PRomUploadJobStore {

    static let queueFileName = "rom-upload-queue.json"

    private let queueFileURL: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    init(rootDirectory: URL) {
        self.queueFileURL = rootDirectory.appendingPathComponent(Self.queueFileName)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    convenience init() {
        self.init(rootDirectory: RomUploadJobStore.defaultRootDirectory())
    }

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

    func allJobs() -> [RomUploadJob] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    func job(id: UUID) -> RomUploadJob? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().first { $0.id == id }
    }

    func add(_ job: RomUploadJob) {
        lock.lock()
        defer { lock.unlock() }
        var jobs = loadLocked()
        jobs.removeAll { $0.id == job.id }
        jobs.append(job)
        saveLocked(jobs)
    }

    func replace(_ job: RomUploadJob) {
        lock.lock()
        defer { lock.unlock() }
        var jobs = loadLocked()
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
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

    private func loadLocked() -> [RomUploadJob] {
        guard let data = try? Data(contentsOf: queueFileURL) else { return [] }
        do {
            return try JSONDecoder().decode([RomUploadJob].self, from: data)
        } catch {
            log("ROM upload queue could not be decoded, continuing with an empty queue: \(error.localizedDescription)")
            return []
        }
    }

    private func saveLocked(_ jobs: [RomUploadJob]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(jobs)
            try data.write(to: queueFileURL, options: .atomic)
        } catch {
            log("ROM upload queue could not be written: \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        Task { @MainActor in
            Logger.data.warning(message)
        }
    }
}
