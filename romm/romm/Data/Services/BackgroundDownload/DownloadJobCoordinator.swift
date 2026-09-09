//
//  DownloadJobCoordinator.swift
//  romm
//

import Foundation
import Observation

/// One queued download as a view needs to read it: the persisted job plus the
/// two figures that are derived rather than stored.
nonisolated struct DownloadJobEntry: Identifiable, Equatable {
    let job: DownloadJob
    /// Share of the announced bytes that have arrived over every file of the job.
    /// Nil when any file has no announced size, because a partly guessed total
    /// would jump as soon as the real size is learned.
    let progress: Double?
    /// Sum of the rates of this job's running transfers, nil until one of them
    /// has measured a rate.
    let bytesPerSecond: Double?

    var id: UUID { job.id }
    var romId: Int { job.romId }
    var state: DownloadJobState { job.state }
    var errorMessage: String? { job.errorMessage }
    /// Everything except a failed job is still on its way.
    var isActive: Bool { job.state != .failed }
}

/// Drives ROM downloads through the background session and keeps the persisted
/// job in step with what the transfers report.
///
/// The transfers belong to a background `URLSession` that the system keeps going
/// while the app is suspended, so no download state may live on a call stack:
/// the persisted job is the state, this type only moves it along.
///
/// Files of one job run at the same time rather than one after another, since the
/// system schedules background transfers itself and a multi disc ROM would
/// otherwise wait for each disc in turn for no gain.
@MainActor
@Observable
final class DownloadJobCoordinator: PBackgroundDownloadEventSink, PDownloadDestinationResolver {

    /// How often a job is restarted on its own after an interruption before it is
    /// handed to the user as failed. A download that cannot get through would
    /// otherwise restart on every launch forever.
    static let maximumAutomaticRestarts = 3

    /// The open jobs, in the order they were queued.
    private(set) var jobs: [DownloadJobEntry] = []

    @ObservationIgnored private let store: PDownloadJobStore
    @ObservationIgnored private let transferClient: PBackgroundTransferClient
    @ObservationIgnored private let finalizer: PROMDownloadFinalizer
    @ObservationIgnored private let apiClient: PRommAPIClient
    /// Only read for its ROM library root, and only for jobs whose destination
    /// this app session did not prepare itself.
    @ObservationIgnored private let romRepository: PLocalROMRepository
    @ObservationIgnored private let logger = Logger.data

    /// Destinations of the jobs prepared in this app session. A destination also
    /// records whether the download created the ROM directory, which decides how
    /// far cleanup may go and cannot be read back off the disk later.
    @ObservationIgnored private var destinations: [UUID: ROMDownloadDestination] = [:]

    /// Last measured rate per job and file name. Rates are momentary, so they
    /// live here rather than in the persisted job.
    @ObservationIgnored private var fileRates: [UUID: [String: Double]] = [:]

    /// Dependencies are resolved in the body rather than as default arguments,
    /// because default arguments are evaluated outside this type's actor
    /// isolation. The transfer client has no default: it owns the background
    /// session identifier and is wired up once at app start.
    init(
        transferClient: PBackgroundTransferClient,
        store: PDownloadJobStore? = nil,
        finalizer: PROMDownloadFinalizer? = nil,
        apiClient: PRommAPIClient? = nil,
        romRepository: PLocalROMRepository? = nil
    ) {
        let romRepository = romRepository ?? LocalROMRepository()
        self.transferClient = transferClient
        self.store = store ?? DownloadJobStore()
        // Built from the same repository, because the finalizer decides where a
        // download goes and this type has to resolve the very same directory.
        self.finalizer = finalizer ?? ROMDownloadFinalizer(repository: romRepository)
        self.apiClient = apiClient ?? DefaultDependencyFactory.shared.apiClient
        self.romRepository = romRepository
        transferClient.eventSink = self
        transferClient.destinationResolver = self
        refreshEntries()
    }

    // MARK: - Derived state

    var activeCount: Int {
        jobs.filter(\.isActive).count
    }

    func entry(forRomId romId: Int) -> DownloadJobEntry? {
        jobs.first { $0.romId == romId }
    }

    func state(forRomId romId: Int) -> DownloadJobState? {
        entry(forRomId: romId)?.state
    }

    func progress(forRomId romId: Int) -> Double? {
        entry(forRomId: romId)?.progress
    }

    func bytesPerSecond(forRomId romId: Int) -> Double? {
        entry(forRomId: romId)?.bytesPerSecond
    }

    func errorMessage(forRomId romId: Int) -> String? {
        entry(forRomId: romId)?.errorMessage
    }

    // MARK: - Queue operations

    /// Queues a ROM and starts a transfer for each of its files.
    /// - Returns: The new job's id, or nil when this ROM is already queued or
    ///   has no files to fetch.
    @discardableResult
    func enqueue(rom: Rom, files: [RomFileInfo]) async -> UUID? {
        guard !files.isEmpty else {
            logger.warning("Download for ROM \(rom.id) was asked for without any files")
            return nil
        }
        if let existing = store.job(romId: rom.id) {
            logger.info("ROM \(rom.id) is already queued as job \(existing.id)")
            return nil
        }

        let job = Self.makeJob(rom: rom, files: files)
        store.add(job)
        refreshEntries()

        await prepareAndStart(job: job, files: job.files)
        return job.id
    }

    private static func makeJob(rom: Rom, files: [RomFileInfo]) -> DownloadJob {
        let platformName = rom.platform?.name ?? rom.platformSlug ?? ""
        return DownloadJob(
            romId: rom.id,
            rom: DownloadJobRomSnapshot(rom: rom),
            platformName: platformName,
            romDirectoryPath: LocalROMRepository.createROMDirectoryPath(
                platformName: platformName,
                romName: rom.name
            ),
            files: files.map {
                DownloadJobFile(fileName: $0.fileName, expectedSizeBytes: $0.fileSizeBytes)
            }
        )
    }

    /// Stops a download, gives back what it wrote and drops it from the queue.
    func cancel(romId: Int) {
        guard let job = store.job(romId: romId) else { return }
        cancel(jobId: job.id)
    }

    func cancel(jobId: UUID) {
        guard var job = store.job(id: jobId) else { return }

        // The state is written before the transfers are stopped, so the
        // cancellations coming back cannot be mistaken for failures.
        job.state = .cancelling
        store.replace(job)
        refreshEntries()

        transferClient.cancelTransfers(forJobId: jobId)
        cleanUpWhatWasWritten(job)
        fileRates[jobId] = nil
        store.remove(jobId: jobId)
        refreshEntries()
        logger.info("Download job \(jobId) for ROM \(job.romId) was cancelled")
    }

    /// Puts a failed job back on its feet, starting the files that are not on
    /// disk yet from the beginning.
    func retry(romId: Int) async {
        guard let job = store.job(romId: romId), job.state == .failed else { return }

        var revived = job
        revived.state = .queued
        revived.errorMessage = nil
        revived.restartCount = 0
        for index in revived.files.indices where revived.files[index].state != .downloaded {
            revived.files[index].state = .pending
            revived.files[index].receivedBytes = 0
        }
        store.replace(revived)
        refreshEntries()

        let outstanding = revived.files.filter { $0.state != .downloaded }
        await prepareAndStart(job: revived, files: outstanding)
    }

    // MARK: - Resumption

    /// Brings the persisted queue back in line with what the system is actually
    /// still transferring. Called once at app start.
    ///
    /// The store only says what the app last knew, so it has to be checked
    /// against `liveTransferKeys()`: ending the app from the app switcher makes
    /// the system drop every transfer without relaunching the app, so a job the
    /// store calls running with no transfer behind it is the normal case here,
    /// not an error.
    func resumeInterruptedJobs() async {
        let liveKeys = await transferClient.liveTransferKeys()
        let storedJobs = store.allJobs()
        guard !storedJobs.isEmpty else {
            refreshEntries()
            return
        }
        logger.info("Reconciling \(storedJobs.count) download job(s) against \(liveKeys.count) live transfer(s)")

        for job in storedJobs {
            await reconcile(job: job, liveKeys: liveKeys)
        }
        refreshEntries()
    }

    private func reconcile(job: DownloadJob, liveKeys: [DownloadTaskKey]) async {
        let isLive: (DownloadJobFile) -> Bool = { file in
            liveKeys.contains(DownloadTaskKey(jobId: job.id, fileName: file.fileName))
        }

        switch job.state {
        case .cancelling:
            // The app went away between asking for the cancel and cleaning up
            // after it, so the cancel is seen through now.
            cancel(jobId: job.id)
            return
        case .failed:
            return
        case .queued, .running, .finalizing:
            break
        }

        // Read back rather than trusting the copy this loop was handed: a job
        // ahead of it in the queue may have been cancelled, which writes the
        // whole file.
        guard let current = store.job(id: job.id) else { return }

        if isComplete(current) {
            finalizeIfComplete(jobId: current.id)
            return
        }

        let interrupted = current.files.filter {
            ($0.state == .pending || $0.state == .running) && !isLive($0)
        }
        guard !interrupted.isEmpty else { return }
        await restart(job: current, files: interrupted)
    }

    /// Counts one more automatic restart and starts the files again, or fails the
    /// job once the cap is reached.
    private func restart(job: DownloadJob, files: [DownloadJobFile]) async {
        guard job.restartCount < Self.maximumAutomaticRestarts else {
            fail(
                jobId: job.id,
                fileName: nil,
                message: "Download stopped after \(Self.maximumAutomaticRestarts) attempts to resume it"
            )
            return
        }

        var resumed = job
        resumed.restartCount += 1
        store.replace(resumed)
        logger.info("Resuming \(files.count) file(s) of download job \(job.id), attempt \(resumed.restartCount)")
        await prepareAndStart(job: resumed, files: files)
    }

    // MARK: - PBackgroundDownloadEventSink

    func downloadProgressed(key: DownloadTaskKey, totalBytesWritten: Int64, bytesPerSecond: Double?) {
        // A checkpoint can arrive after the job it belongs to has finished, been
        // cancelled or failed. It must never lift such a job back into a running
        // state, or the queue keeps showing a download that is long over.
        guard let job = store.job(id: key.jobId), job.state == .queued || job.state == .running else { return }
        guard let file = file(named: key.fileName, of: job),
              file.state == .pending || file.state == .running else { return }

        // The job state goes first: `replace` writes the whole job, so it has to
        // happen before the file of that job is mutated in place.
        if job.state == .queued {
            var running = job
            running.state = .running
            store.replace(running)
        }
        store.updateFile(jobId: key.jobId, fileName: key.fileName) {
            $0.state = .running
            $0.receivedBytes = totalBytesWritten
        }
        if let bytesPerSecond {
            fileRates[key.jobId, default: [:]][key.fileName] = bytesPerSecond
        }
        refreshEntries()
    }

    func downloadFinished(key: DownloadTaskKey, bytesOnDisk: Int64) {
        guard let job = openJob(id: key.jobId),
              let file = file(named: key.fileName, of: job), file.state != .downloaded else { return }

        store.updateFile(jobId: key.jobId, fileName: key.fileName) {
            $0.state = .downloaded
            $0.receivedBytes = bytesOnDisk
        }
        fileRates[key.jobId]?[key.fileName] = nil
        refreshEntries()
        finalizeIfComplete(jobId: key.jobId)
    }

    func downloadFailed(key: DownloadTaskKey, error: Error, isCancellation: Bool) {
        // A cancellation is the app's own doing and is reported back for every
        // transfer it stopped, including ones whose job is already gone.
        guard !isCancellation else {
            fileRates[key.jobId]?[key.fileName] = nil
            return
        }
        logger.error("Transfer \(key.fileName) of download job \(key.jobId) failed: \(error)")
        fail(jobId: key.jobId, fileName: key.fileName, message: error.localizedDescription)
    }

    func downloadRejected(key: DownloadTaskKey, statusCode: Int, serverMessage: String?) {
        guard let job = openJob(id: key.jobId), let file = file(named: key.fileName, of: job) else { return }

        // RomM 5.1 serves a file under api/roms/{id}/content/{fileName}, RomM 5.0
        // only knows the bare content endpoint. A 404 on the per file path is the
        // older server saying so, and the file is started over on the legacy one.
        if statusCode == 404, !file.usesLegacyContentPath {
            retryOnLegacyContentPath(key: key)
            return
        }

        var message = "Server rejected the download of \(key.fileName) with status \(statusCode)"
        if let serverMessage, !serverMessage.isEmpty {
            message += ": \(serverMessage)"
        }
        fail(jobId: key.jobId, fileName: key.fileName, message: message)
    }

    func sessionDidFinishEvents() {
        // Every write this class makes is synchronous, so by the time the events
        // are through the queue on disk is up to date and only the observable
        // copy has to catch up.
        refreshEntries()
        logger.debug("Background session delivered all pending events")
    }

    /// The job an event belongs to, unless it has been cancelled or failed and
    /// must not be moved along any further.
    private func openJob(id: UUID) -> DownloadJob? {
        guard let job = store.job(id: id), job.state != .cancelling, job.state != .failed else { return nil }
        return job
    }

    private func file(named fileName: String, of job: DownloadJob) -> DownloadJobFile? {
        job.files.first { $0.fileName == fileName }
    }

    // MARK: - PDownloadDestinationResolver

    /// Taken from the job's destination, the same value that is handed to the
    /// finalizer when the job is finished, so the delegate cannot put a file
    /// anywhere the finalizer will not look for it.
    func destinationURL(for key: DownloadTaskKey) -> URL? {
        guard let job = store.job(id: key.jobId), file(named: key.fileName, of: job) != nil else { return nil }
        return destination(for: job).directoryURL.appendingPathComponent(key.fileName)
    }

    // MARK: - Transfers

    /// Checks storage, makes the ROM directory and starts the given files.
    ///
    /// Only the files handed in are started, so a job that comes back with some
    /// of its transfers still alive does not get a second transfer for them.
    private func prepareAndStart(job: DownloadJob, files: [DownloadJobFile]) async {
        guard await prepareDestination(for: job) else { return }

        // Preparing is the one await in here, so the job may have been cancelled
        // in the meantime.
        guard var current = store.job(id: job.id), current.state == .queued || current.state == .running else { return }

        // A job can come back with nothing left to transfer, for instance when
        // it failed while it was being finished and every file was already on
        // disk. Calling it running and starting nothing would leave it on the
        // queue with nobody to move it along.
        guard !files.isEmpty else {
            finalizeIfComplete(jobId: current.id)
            return
        }

        current.state = .running
        store.replace(current)

        for file in files {
            startTransfer(job: current, file: file)
        }
        refreshEntries()
    }

    /// - Returns: Whether the job can go ahead. A job that cannot be prepared is
    ///   failed here.
    private func prepareDestination(for job: DownloadJob) async -> Bool {
        do {
            let destination = try await finalizer.prepare(
                rom: rom(of: job),
                files: romFileInfos(of: job),
                // Everything else that is open but not written yet is promised
                // storage as well, so two large ROMs are checked against the
                // volume together instead of each on its own.
                reservedBytes: outstandingBytes(excludingJobId: job.id)
            )
            destinations[job.id] = destination
            adoptDirectoryPath(of: destination, forJobId: job.id)
            return true
        } catch {
            logger.error("Download job \(job.id) could not be prepared: \(error)")
            fail(jobId: job.id, fileName: nil, message: error.localizedDescription)
            return false
        }
    }

    private func startTransfer(job: DownloadJob, file: DownloadJobFile) {
        do {
            let request = try apiClient.makeROMContentDownloadRequest(
                romId: job.romId,
                fileName: file.fileName,
                usesLegacyContentPath: file.usesLegacyContentPath
            )
            store.updateFile(jobId: job.id, fileName: file.fileName) { $0.state = .running }
            transferClient.start(request: request, key: DownloadTaskKey(jobId: job.id, fileName: file.fileName))
            refreshEntries()
        } catch {
            logger.error("Download job \(job.id) could not build a request for \(file.fileName): \(error)")
            fail(jobId: job.id, fileName: file.fileName, message: error.localizedDescription)
        }
    }

    private func retryOnLegacyContentPath(key: DownloadTaskKey) {
        logger.info("Per file content path answered 404 for \(key.fileName), retrying on the legacy path")
        store.updateFile(jobId: key.jobId, fileName: key.fileName) {
            $0.usesLegacyContentPath = true
            $0.state = .pending
            $0.receivedBytes = 0
        }
        guard let refreshed = store.job(id: key.jobId),
              let retried = file(named: key.fileName, of: refreshed) else { return }
        startTransfer(job: refreshed, file: retried)
    }

    // MARK: - Completion and failure

    private func finalizeIfComplete(jobId: UUID) {
        guard let job = store.job(id: jobId), canFinalize(job) else { return }

        var finalizing = job
        finalizing.state = .finalizing
        store.replace(finalizing)
        refreshEntries()

        storeFinishedROM(job)
    }

    private func canFinalize(_ job: DownloadJob) -> Bool {
        switch job.state {
        case .cancelling, .failed: return false
        case .queued, .running, .finalizing: return isComplete(job)
        }
    }

    /// Every file of the job is on disk. Read off the file states, never off the
    /// byte counts: the announced size is only a hint, since the server may build
    /// an archive while it serves it.
    private func isComplete(_ job: DownloadJob) -> Bool {
        !job.files.isEmpty && job.files.allSatisfy { $0.state == .downloaded }
    }

    private func storeFinishedROM(_ job: DownloadJob) {
        do {
            let stored = try finalizer.finish(
                rom: rom(of: job),
                files: romFileInfos(of: job),
                destination: destination(for: job)
            )
            destinations[job.id] = nil
            fileRates[job.id] = nil
            store.remove(jobId: job.id)
            refreshEntries()
            logger.info("Download job \(job.id) stored ROM \(stored.id) with \(stored.files.count) file(s)")
        } catch {
            logger.error("Download job \(job.id) could not be finished: \(error)")
            fail(jobId: job.id, fileName: nil, message: error.localizedDescription)
        }
    }

    /// Stops a job for good and leaves it in the queue with its reason, so the
    /// user can see what happened and ask for it again.
    private func fail(jobId: UUID, fileName: String?, message: String) {
        guard store.job(id: jobId)?.state != .cancelling else { return }
        if let fileName {
            store.updateFile(jobId: jobId, fileName: fileName) { $0.state = .failed }
        }
        guard var job = store.job(id: jobId) else { return }
        job.state = .failed
        job.errorMessage = message
        store.replace(job)

        transferClient.cancelTransfers(forJobId: jobId)
        cleanUpWhatWasWritten(job)
        fileRates[jobId] = nil
        refreshEntries()
    }

    /// Hands back the bytes this job put on disk.
    ///
    /// A job that never wrote anything must not clean up: its ROM directory can
    /// hold an earlier download of the same ROM, and the file names a job owns
    /// are exactly the names of that download.
    private func cleanUpWhatWasWritten(_ job: DownloadJob) {
        if let prepared = destinations[job.id] {
            finalizer.cleanUp(prepared)
        } else if job.files.contains(where: { $0.receivedBytes > 0 || $0.state == .downloaded }) {
            finalizer.cleanUp(rebuiltDestination(for: job))
        }
        destinations[job.id] = nil
    }

    private func destination(for job: DownloadJob) -> ROMDownloadDestination {
        if let prepared = destinations[job.id] { return prepared }
        let rebuilt = rebuiltDestination(for: job)
        destinations[job.id] = rebuilt
        return rebuilt
    }

    /// The destination of a job that was prepared in an earlier app session.
    ///
    /// The directory the finalizer prepared back then is not persisted as an
    /// absolute URL, since the app container path is not stable across launches,
    /// so it is put together again from the path the job carries.
    ///
    /// Whether that session created the ROM directory is not persisted either,
    /// so this assumes it did not: cleanup then takes back only the files the
    /// job owns and leaves the directory, which cannot take foreign files with
    /// it.
    private func rebuiltDestination(for job: DownloadJob) -> ROMDownloadDestination {
        ROMDownloadDestination(
            relativePath: job.romDirectoryPath,
            directoryURL: romRepository.romsBaseURL.appendingPathComponent(job.romDirectoryPath),
            didCreateDirectory: false,
            ownedFileNames: job.files.map(\.fileName)
        )
    }

    /// Writes the directory the finalizer prepared back into the job.
    ///
    /// The job is persisted before anything is prepared and carries a directory
    /// path from the moment it was queued. `prepare` is what decides where the
    /// files really go, so its answer replaces that first guess and is what a
    /// later app session rebuilds the destination from.
    private func adoptDirectoryPath(of destination: ROMDownloadDestination, forJobId jobId: UUID) {
        guard var job = store.job(id: jobId), job.romDirectoryPath != destination.relativePath else { return }
        job.romDirectoryPath = destination.relativePath
        store.replace(job)
    }

    // MARK: - Job helpers

    private func rom(of job: DownloadJob) -> Rom {
        var rom = job.rom.toRom()
        // The finalizer files a ROM under its platform name and falls back to the
        // slug, while the job carries the name that was resolved when it was
        // queued. Handing that name back keeps the directory and the metadata the
        // same after a restart.
        rom.platform = Platform(
            id: job.rom.platformId,
            name: job.platformName,
            slug: job.rom.platformSlug ?? ""
        )
        return rom
    }

    private func romFileInfos(of job: DownloadJob) -> [RomFileInfo] {
        job.files.map {
            RomFileInfo(
                id: $0.fileName,
                fileName: $0.fileName,
                fileSizeBytes: $0.expectedSizeBytes,
                fileExtension: ($0.fileName as NSString).pathExtension
            )
        }
    }

    /// Bytes that other open jobs still expect to write. A cancelled or failed
    /// job is not owed any storage.
    private func outstandingBytes(excludingJobId excluded: UUID) -> Int64 {
        store.allJobs().reduce(into: Int64(0)) { total, job in
            guard job.id != excluded, job.state != .failed, job.state != .cancelling else { return }
            for file in job.files where file.state != .downloaded {
                total += max(0, file.expectedSizeBytes - file.receivedBytes)
            }
        }
    }

    private func progress(of job: DownloadJob) -> Double? {
        var expected: Int64 = 0
        var received: Int64 = 0
        for file in job.files {
            // One unknown size makes the whole total unknown, an estimate would
            // only be a moving target.
            guard file.expectedSizeBytes > 0 else { return nil }
            expected += file.expectedSizeBytes
            received += file.receivedBytes
        }
        guard expected > 0 else { return nil }
        // The announced size is a hint the arriving bytes can exceed, so the
        // share is capped instead of running past a full bar.
        return min(max(Double(received) / Double(expected), 0), 1)
    }

    /// Rates of the running files added up, which is the figure that means
    /// something to the user while several files of one ROM transfer at once.
    private func rate(of job: DownloadJob) -> Double? {
        guard let rates = fileRates[job.id], !rates.isEmpty else { return nil }
        return rates.values.reduce(0, +)
    }

    private func refreshEntries() {
        jobs = store.allJobs().map { job in
            DownloadJobEntry(
                job: job,
                progress: progress(of: job),
                bytesPerSecond: rate(of: job)
            )
        }
    }
}
