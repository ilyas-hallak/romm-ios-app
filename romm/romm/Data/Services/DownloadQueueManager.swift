import Foundation
import Observation

/// The app-wide download queue as the screens see it: a flat list of ROMs with
/// a status each.
///
/// The transfers themselves belong to `DownloadJobCoordinator` and a background
/// `URLSession`, so they carry on while the app is suspended and survive a
/// restart. This type owns that coordinator and turns its persisted jobs into
/// the rows the queue screen, the ROM detail button and the tab badge read.
///
/// It keeps one thing of its own: a job that came through is dropped by the
/// coordinator, while the queue screen still wants to show it under "Completed"
/// until the user clears it. Those settled rows live here, everything else is
/// derived from the coordinator.
@Observable
@MainActor
final class DownloadQueueManager {
    static let shared = DownloadQueueManager()

    /// Rows for ROMs whose file list is still being fetched. They have no job
    /// yet, and without them a tapped Download button would spring back to
    /// "Download" until the server answered.
    private var pendingTasks: [DownloadTask] = []

    /// Rows the coordinator has let go of: stored, cancelled, or dropped before
    /// they ever became a job.
    private var settledTasks: [DownloadTask] = []

    @ObservationIgnored private let coordinator: DownloadJobCoordinator
    @ObservationIgnored private let transferClient: PBackgroundTransferClient
    @ObservationIgnored private let fileListProvider: PROMFileListProvider
    @ObservationIgnored private let continuedTaskController: PDownloadContinuedTaskController
    @ObservationIgnored private let logger = Logger.data

    /// The live activity of each ROM being fetched, keyed by ROM id.
    ///
    /// The UUID is made up here rather than taken from the job, because the
    /// activity has to be asked for while the user's tap is still on the stack,
    /// and the job only comes into being after `enqueue(rom:)` has awaited the
    /// file list. The controller wants a stable key and nothing more.
    @ObservationIgnored private var activityIds: [Int: UUID] = [:]

    /// The rows as of the last reconciliation, keyed by ROM id. A job that has
    /// gone from the coordinator can only be turned into a settled row from what
    /// was last known about it.
    @ObservationIgnored private var lastKnownTasks: [Int: DownloadTask] = [:]

    /// What to do with a job the app itself asked to end, decided when the ask
    /// happens and read when the job leaves the coordinator. Without it a
    /// cancelled job would be indistinguishable from one that came through.
    @ObservationIgnored private var disposals: [Int: Disposal] = [:]

    /// The in flight file list lookups, so cancelling a download that has not
    /// become a job yet actually stops it.
    @ObservationIgnored private var startTasks: [Int: Task<Void, Never>] = [:]

    private enum Disposal {
        case markCancelled
        case drop
    }

    /// Dependencies are resolved in the body rather than as default arguments,
    /// because default arguments are evaluated outside this type's actor
    /// isolation. A test that hands in its own coordinator has to hand in the
    /// same transfer client, or the real background session gets built.
    init(
        transferClient: PBackgroundTransferClient? = nil,
        coordinator: DownloadJobCoordinator? = nil,
        fileListProvider: PROMFileListProvider? = nil,
        continuedTaskController: PDownloadContinuedTaskController? = nil
    ) {
        let client = transferClient ?? BackgroundDownloadSession.shared
        let jobCoordinator = coordinator ?? DownloadJobCoordinator(transferClient: client)
        self.transferClient = client
        self.coordinator = jobCoordinator
        self.fileListProvider = fileListProvider
            ?? ROMDetailsFileListProvider(apiClient: DefaultDependencyFactory.shared.apiClient)
        self.continuedTaskController = continuedTaskController ?? DownloadContinuedTaskController()

        // A coordinator built here wires itself up, an injected one may have been
        // built against another client, so the wiring is stated either way.
        client.eventSink = jobCoordinator
        client.destinationResolver = jobCoordinator

        // The queue file may already hold jobs from an earlier launch.
        lastKnownTasks = Dictionary(
            uniqueKeysWithValues: jobCoordinator.jobs.map { entry in (entry.romId, task(from: entry)) }
        )
        observeCoordinatorJobs()
    }

    // MARK: - Derived state

    /// Every row, active ones first, then what has settled. That order is also
    /// what `status(forRomId:)` wants: a fresh attempt at a ROM outranks the
    /// leftover row of an earlier one.
    ///
    /// Reading `coordinator.jobs` in here is enough for a view to be told about
    /// a change: Observation registers the access itself, whichever object the
    /// property is reached through, so a body that reads `tasks` also tracks
    /// the coordinator's `jobs`.
    var tasks: [DownloadTask] {
        pendingTasks + coordinator.jobs.map { task(from: $0) } + settledTasks
    }

    /// Number of downloads still queued or in progress.
    var activeCount: Int {
        tasks.filter { $0.isActive }.count
    }

    /// Count of finished downloads, used by the Downloads tab to refresh its list.
    var finishedCount: Int {
        tasks.filter { if case .finished = $0.status { return true } else { return false } }.count
    }

    func status(forRomId id: Int) -> DownloadTask.Status? {
        tasks.first { $0.id == id }?.status
    }

    // MARK: - Queue operations

    /// Adds a ROM to the queue. No-op if it is already queued, downloading or
    /// finished. A previously failed download is started again.
    ///
    /// Stays synchronous for its callers: the file list is fetched in a task of
    /// its own, and the row shows up as queued straight away.
    func enqueue(rom: Rom) {
        guard claimAttempt(for: rom) else { return }

        // Asked for here and nowhere later, because the scheduler only grants a
        // continued processing task to a foreground user action, and this call
        // is the last point that still runs on the tap that caused it.
        startActivity(for: rom)

        pendingTasks.append(DownloadTask(
            id: rom.id,
            rom: rom,
            name: rom.name,
            platformSlug: rom.platformSlug,
            status: .queued
        ))
        startTasks[rom.id] = Task { [weak self] in
            await self?.start(rom: rom)
        }
    }

    /// Whether a fresh attempt at this ROM is due, clearing the leftovers of an
    /// earlier one out of the way when it is.
    private func claimAttempt(for rom: Rom) -> Bool {
        if let entry = coordinator.entry(forRomId: rom.id) {
            // A failed job is put back on its feet rather than queued twice.
            if entry.state == .failed {
                retry(id: rom.id)
            }
            return false
        }
        guard startTasks[rom.id] == nil else { return false }
        if let settled = settledTasks.first(where: { $0.id == rom.id }) {
            // The ROM is already on the device, nothing to fetch again.
            if case .finished = settled.status { return false }
            // A cancelled or failed attempt makes way for the new one.
            settledTasks.removeAll { $0.id == rom.id }
        }
        return true
    }

    /// Stops a download and takes back what it wrote. Anything that got as far
    /// as a transfer leaves a cancelled row behind as feedback, a download still
    /// waiting for its first one is simply gone, the same as swiping it away.
    func cancel(id: Int) {
        stopStarting(romId: id)
        // Ends the activity here rather than only in `reconcile`, which never
        // hears about a download that had no job to begin with.
        finishActivity(romId: id, success: false)
        pendingTasks.removeAll { $0.id == id }

        guard let entry = coordinator.entry(forRomId: id) else { return }
        // A job still waiting for its first transfer wrote nothing and has
        // nothing worth reporting, so its row goes rather than turning up as
        // cancelled work the user then has to clear.
        disposals[id] = entry.state == .queued ? .drop : .markCancelled
        coordinator.cancel(romId: id)
        reconcile()
    }

    /// Removes a queued, finished, failed or cancelled row. A queued one is
    /// stopped on the way out, to the same end as its Cancel button. A download
    /// that is transferring or filing its files away is left alone and goes
    /// through `cancel(id:)` instead, which also gives back the bytes it wrote.
    func remove(id: Int) {
        if let entry = coordinator.entry(forRomId: id) {
            switch entry.state {
            case .running, .finalizing, .cancelling: return
            case .queued, .failed: break
            }
            disposals[id] = .drop
            coordinator.cancel(romId: id)
            reconcile()
        }
        stopStarting(romId: id)
        finishActivity(romId: id, success: false)
        pendingTasks.removeAll { $0.id == id }
        settledTasks.removeAll { $0.id == id }
    }

    func retry(id: Int) {
        if let entry = coordinator.entry(forRomId: id) {
            guard entry.state == .failed else { return }
            // Also a foreground user action, and the activity of the attempt
            // that failed is over, so this one gets its own.
            startActivity(for: entry.job.rom.toRom())
            Task { await coordinator.retry(romId: id) }
            return
        }
        // A download that failed before it ever became a job, for instance
        // because its file list could not be fetched, is started from scratch.
        guard let settled = settledTasks.first(where: { $0.id == id }),
              case .failed = settled.status else { return }
        settledTasks.removeAll { $0.id == id }
        enqueue(rom: settled.rom)
    }

    /// Clears finished, failed and cancelled rows, leaving the running ones.
    func clearCompleted() {
        settledTasks.removeAll()
        for entry in coordinator.jobs where entry.state == .failed {
            disposals[entry.romId] = .drop
            coordinator.cancel(romId: entry.romId)
        }
        reconcile()
    }

    private func stopStarting(romId: Int) {
        startTasks.removeValue(forKey: romId)?.cancel()
    }

    // MARK: - App lifecycle

    /// Whether the events of that background session identifier are this queue's
    /// to deal with.
    ///
    /// The identifier is all the system hands over when it relaunches the app for
    /// session events, and which session it stands for is knowledge of this
    /// layer, not of the app delegate.
    func handlesBackgroundSession(identifier: String) -> Bool {
        identifier == transferClient.identifier
    }

    /// Takes the completion handler the system hands over when it relaunches the
    /// app only to deliver background session events, and makes sure the session
    /// that delivers them exists.
    func handleBackgroundSessionEvents(completionHandler: @escaping () -> Void) {
        transferClient.setLaunchCompletionHandler(completionHandler)
    }

    /// Brings the persisted queue back in line with what the system is still
    /// transferring. Called once at app start.
    func resumeInterruptedJobs() async {
        await coordinator.resumeInterruptedJobs()
        reconcile()
    }

    // MARK: - Starting a download

    private func start(rom: Rom) async {
        defer { startTasks[rom.id] = nil }
        do {
            let files = try await fileListProvider.files(for: rom)
            guard !Task.isCancelled else {
                pendingTasks.removeAll { $0.id == rom.id }
                return
            }
            await coordinator.enqueue(rom: rom, files: files)
            pendingTasks.removeAll { $0.id == rom.id }
            reconcile()
        } catch {
            pendingTasks.removeAll { $0.id == rom.id }
            guard !Task.isCancelled else { return }
            settleAsFailed(rom: rom, error: error)
        }
    }

    /// Leaves a failed row behind for a download that never became a job: the
    /// row must not just vanish, or a tapped Download button would leave the
    /// user with nothing at all. Nothing downstream can end its activity
    /// either, so that happens here too.
    private func settleAsFailed(rom: Rom, error: Error) {
        logger.error("Queue: could not work out the files of ROM \(rom.id): \(error)")
        finishActivity(romId: rom.id, success: false)
        settledTasks.removeAll { $0.id == rom.id }
        settledTasks.append(DownloadTask(
            id: rom.id,
            rom: rom,
            name: rom.name,
            platformSlug: rom.platformSlug,
            status: .failed(error.localizedDescription)
        ))
    }

    // MARK: - Coordinator bridge

    /// Notices when the coordinator lets go of a job.
    ///
    /// A job that came through is removed from the coordinator's list, so its
    /// disappearance is the only news that it was stored, and this facade hears
    /// nothing else: the transfers report to the coordinator, never here.
    private func observeCoordinatorJobs() {
        withObservationTracking {
            _ = coordinator.jobs
        } onChange: { [weak self] in
            // The change is not applied yet when this fires, so the list is read
            // a turn later. Tracking only fires once and is renewed there too.
            Task { @MainActor [weak self] in
                self?.reconcile()
                self?.observeCoordinatorJobs()
            }
        }
    }

    /// Turns jobs that have gone from the coordinator into settled rows and
    /// takes a fresh reading of the ones that are left.
    private func reconcile() {
        let entries = coordinator.jobs
        let current = entries.map { task(from: $0) }
        let currentIds = Set(current.map(\.id))

        for (romId, previous) in lastKnownTasks where !currentIds.contains(romId) {
            settleVanishedJob(romId: romId, lastKnown: previous)
        }
        refreshActivities(for: entries)

        lastKnownTasks = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        // A ROM the coordinator has taken on again has no business also showing
        // the settled row of an earlier attempt.
        settledTasks.removeAll { currentIds.contains($0.id) }
    }

    /// Works out what a job leaving the coordinator leaves behind, from what the
    /// app asked for and what was last known about it.
    private func settleVanishedJob(romId: Int, lastKnown previous: DownloadTask) {
        switch disposals.removeValue(forKey: romId) {
        case .drop:
            finishActivity(romId: romId, success: false)
        case .markCancelled:
            finishActivity(romId: romId, success: false)
            settledTasks.append(settled(previous, as: .cancelled))
        case nil:
            // Nobody asked for this one to end, so either it was stored, or the
            // app was away while a cancel of an earlier session was seen
            // through, which the last known status is what tells them apart.
            let wasCancelled = previous.status == .cancelled
            finishActivity(romId: romId, success: !wasCancelled)
            settledTasks.append(settled(previous, as: wasCancelled ? .cancelled : .finished))
        }
    }

    /// The one moment this facade is told about progress, and it is already
    /// throttled upstream, so the activities are fed straight from here. Still
    /// reading the previous rows, because an activity is only ended on the step
    /// into a final state, not for as long as the job sits in one.
    private func refreshActivities(for entries: [DownloadJobEntry]) {
        for entry in entries {
            refreshActivity(for: entry, previousStatus: lastKnownTasks[entry.romId]?.status)
        }
    }

    private func task(from entry: DownloadJobEntry) -> DownloadTask {
        DownloadTask(
            id: entry.romId,
            rom: entry.job.rom.toRom(),
            name: entry.job.rom.name,
            platformSlug: entry.job.rom.platformSlug,
            status: status(of: entry)
        )
    }

    private func status(of entry: DownloadJobEntry) -> DownloadTask.Status {
        switch entry.state {
        case .queued:
            return .queued
        case .running:
            return .downloading(progress: entry.progress, bytesPerSecond: entry.bytesPerSecond)
        case .finalizing:
            return .finalizing
        case .cancelling:
            // Reported as cancelled rather than as a state of its own: the
            // transfers are already stopped, the winding down is bookkeeping the
            // user has no use for.
            return .cancelled
        case .failed:
            return .failed(entry.errorMessage ?? "Download failed")
        }
    }

    private func settled(_ task: DownloadTask, as status: DownloadTask.Status) -> DownloadTask {
        var copy = task
        copy.status = status
        return copy
    }

    // MARK: - Live activity

    /// First subtitle of every activity, and what it stays on until a
    /// transfer has a rate to report.
    private static let preparingSubtitle = "Preparing"

    /// Asks for the activity of a ROM that is about to be fetched. A ROM that
    /// already has one keeps it, so tapping Download twice does not put two
    /// activities on screen for one download.
    ///
    /// Nothing downstream may depend on this: on the simulator and before iOS 26
    /// there is no activity at all, and the controller says so by staying quiet.
    private func startActivity(for rom: Rom) {
        guard activityIds[rom.id] == nil else { return }

        let activityId = UUID()
        activityIds[rom.id] = activityId
        continuedTaskController.start(
            jobId: activityId,
            title: rom.name,
            subtitle: Self.preparingSubtitle,
            totalBytes: rom.sizeBytes.map { Int64($0) }
        )
    }

    /// Feeds one job's activity, or ends it when the job has just stopped for
    /// good without leaving the coordinator.
    private func refreshActivity(for entry: DownloadJobEntry, previousStatus: DownloadTask.Status?) {
        guard let activityId = activityIds[entry.romId] else { return }

        switch entry.state {
        case .queued, .running, .finalizing:
            continuedTaskController.update(
                jobId: activityId,
                completedBytes: receivedBytes(of: entry),
                totalBytes: expectedBytes(of: entry),
                subtitle: subtitle(for: entry)
            )
        case .failed, .cancelling:
            // A failed job stays in the coordinator, so nothing else would ever
            // take its activity down. Only on the step into that state though:
            // `retry` hands out a new activity while the job it revives is
            // still failed, and a reconciliation in between must leave it be.
            guard previousStatus != status(of: entry) else { return }
            finishActivity(romId: entry.romId, success: false)
        }
    }

    private func finishActivity(romId: Int, success: Bool) {
        guard let activityId = activityIds.removeValue(forKey: romId) else { return }
        continuedTaskController.finish(jobId: activityId, success: success)
    }

    /// Second line of the activity, in the same words the queue screen uses and
    /// through the same rate formatting, so the two never disagree.
    private func subtitle(for entry: DownloadJobEntry) -> String {
        switch entry.state {
        case .running:
            return DownloadTask.formattedRate(entry.bytesPerSecond) ?? "Downloading…"
        case .finalizing:
            return "Finishing up…"
        case .queued, .cancelling, .failed:
            // Queued stays on "Preparing" rather than "Queued" because the first
            // transfer is seconds away. The two ended states never get here,
            // `refreshActivity` finishes instead.
            return Self.preparingSubtitle
        }
    }

    /// What the transfers have reported for every file of the job. The entry
    /// carries the share of the whole, the activity's bar wants the bytes.
    private func receivedBytes(of entry: DownloadJobEntry) -> Int64 {
        entry.job.files.reduce(0) { $0 + $1.receivedBytes }
    }

    /// Announced size of the whole job, or nil when a file has none, following
    /// the same rule as the progress share: a partly guessed total would move.
    private func expectedBytes(of entry: DownloadJobEntry) -> Int64? {
        var total: Int64 = 0
        for file in entry.job.files {
            guard file.expectedSizeBytes > 0 else { return nil }
            total += file.expectedSizeBytes
        }
        return total > 0 ? total : nil
    }
}
