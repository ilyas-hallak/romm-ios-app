//
//  DownloadContinuedTaskController.swift
//  romm
//

import Foundation
import BackgroundTasks

/// Shows a system rendered live activity for a running download job.
///
/// The transfer itself is moved by a background `URLSession` and needs none of
/// this: `BGContinuedProcessingTask` only buys the on screen progress the user
/// sees while the app is in the background. So every failure in here is
/// swallowed, the worst outcome is a download that runs without an activity.
///
/// iOS 26 and later only. On anything older every call is a no-op, which is why
/// the deployment target does not have to move.
@MainActor
protocol PDownloadContinuedTaskController: AnyObject {
    /// Registers a launch handler and submits a request for `jobId`.
    ///
    /// Must come out of a foreground user action, the scheduler rejects continued
    /// processing requests that do not. Calling it twice for the same job while
    /// its activity is still up does nothing. `totalBytes` may be nil when the
    /// size is not known yet, `update` can supply it later.
    func start(jobId: UUID, title: String, subtitle: String, totalBytes: Int64?)

    /// Moves the activity's progress bar and, when `subtitle` differs from what
    /// is on screen, its text.
    ///
    /// Has to be called regularly: the scheduler expires tasks whose progress
    /// looks stalled, see `BGTask.h` line 124.
    func update(jobId: UUID, completedBytes: Int64, totalBytes: Int64?, subtitle: String?)

    /// Ends the activity for `jobId`. Harmless for a job that has none, and
    /// harmless a second time.
    func finish(jobId: UUID, success: Bool)
}

// MARK: - Scheduler seam

/// The one task the controller is handed by the scheduler, as much of it as the
/// controller touches.
///
/// `BGContinuedProcessingTask` is created by the system and cannot be
/// instantiated, so a test can only drive the controller through a stand-in.
@MainActor
protocol PContinuedProcessingTaskHandle: AnyObject {
    /// Written straight onto the task's `Progress`. Never through a child
    /// progress: a composed progress hierarchy does not reach the system
    /// rendered activity, the bar just sits still (FB21338185).
    var totalUnitCount: Int64 { get set }
    var completedUnitCount: Int64 { get set }

    func updateTitle(_ title: String, subtitle: String)

    /// The system calls this shortly before it takes the task's runtime away.
    func setExpirationHandler(_ handler: (() -> Void)?)

    /// Exactly once per task, or the app is faulted for holding on to runtime.
    func setCompleted(success: Bool)
}

/// Registering and submitting as one step, because for continued processing
/// tasks they belong together: the handler for an identifier has to be in place
/// before a request under that identifier is submitted, otherwise the submit
/// raises `NSInternalInconsistencyException`. A single handler registered for
/// the permitted wildcard does not stand in for the concrete identifiers either,
/// that crashes the same way, so every identifier gets a handler of its own
/// right before its submit.
@MainActor
protocol PContinuedProcessingScheduler: AnyObject {
    /// False on anything before iOS 26, which lets the controller skip its work
    /// entirely instead of building identifiers nobody will use.
    var isSupported: Bool { get }

    /// Registers `launchHandler` for `identifier` and submits a request under
    /// the same identifier. False when either half was refused, which the caller
    /// treats as "no activity" and nothing worse.
    ///
    /// `launchHandler` runs when the system actually grants the task runtime,
    /// which can be a moment after the submit or, under load, not at all.
    func submit(
        identifier: String,
        title: String,
        subtitle: String,
        launchHandler: @escaping @MainActor (PContinuedProcessingTaskHandle) -> Void
    ) -> Bool

    /// Withdraws a request that was submitted but never granted runtime. Needed
    /// when a download finishes before its activity ever came up.
    func cancelPendingRequest(identifier: String)
}

// MARK: - Controller

/// Unverified, and all of it failing towards a missing activity rather than a
/// broken download: how much of an identifier the `.*` of a permitted identifier
/// covers, how many continued processing tasks may be in flight at once, which
/// of `Progress`'s text properties the system actually renders, and what the
/// activity shows while the total size is unknown.
@MainActor
final class DownloadContinuedTaskController: PDownloadContinuedTaskController {

    /// What the controller knows about one job's activity.
    private struct ActiveTask {
        let identifier: String
        var title: String
        var subtitle: String
        var totalBytes: Int64
        var completedBytes: Int64
        /// Nil until the system grants the task runtime and hands over the task.
        /// Until then there is a submitted request and nothing to write to.
        var handle: PContinuedProcessingTaskHandle?

        /// Folds a progress report into something the bar can show.
        ///
        /// The announced size is a hint, the server may build an archive while it
        /// serves it, so the transferred count can pass it. Growing the total
        /// keeps the bar at the end rather than letting it read over 100 percent.
        mutating func record(completedBytes: Int64, totalBytes: Int64?, subtitle: String?) {
            self.completedBytes = max(0, completedBytes)
            if let totalBytes, totalBytes > 0 {
                self.totalBytes = totalBytes
            }
            self.totalBytes = max(self.totalBytes, self.completedBytes)
            if let subtitle {
                self.subtitle = subtitle
            }
        }
    }

    private let scheduler: PContinuedProcessingScheduler
    private let identifierPrefix: String
    private let logger = Logger.data

    private var active: [UUID: ActiveTask] = [:]

    /// Every identifier this process has registered a handler for.
    ///
    /// `BGTaskScheduler` kills the app on a second registration of the same
    /// identifier (`BGTaskScheduler.h` line 90), and a registration cannot be
    /// undone, so a job that gets a second activity later in the same process,
    /// for instance after the queue restarted it, has to run under a fresh
    /// identifier.
    private var usedIdentifiers: Set<String> = []

    /// Takes its scheduler and its prefix so a test can run without touching
    /// `BGTaskScheduler`, production code passes neither. `scheduler` defaults to
    /// nil rather than to a `BGContinuedProcessingScheduler()`, because a default
    /// argument is evaluated outside this main actor bound type.
    init(
        scheduler: PContinuedProcessingScheduler? = nil,
        identifierPrefix: String = DownloadContinuedTaskController.defaultIdentifierPrefix
    ) {
        self.scheduler = scheduler ?? BGContinuedProcessingScheduler()
        self.identifierPrefix = identifierPrefix
    }

    /// Matches the `BGTaskSchedulerPermittedIdentifiers` wildcard in Info.plist,
    /// `$(PRODUCT_BUNDLE_IDENTIFIER).download.*`. The header's own example
    /// replaces that `.*` with a single segment (`BGTaskRequest.h` line 163), so
    /// `identifier(forJobId:)` keeps to one segment with no dot in it.
    nonisolated static let defaultIdentifierPrefix =
        "\(Bundle.main.bundleIdentifier ?? "com.romm.app").download"

    // MARK: - PDownloadContinuedTaskController

    func start(jobId: UUID, title: String, subtitle: String, totalBytes: Int64?) {
        guard scheduler.isSupported else { return }
        // A job that already has an activity keeps it. Submitting again would
        // register a second identifier for one download, and the user would see
        // two activities for it.
        guard active[jobId] == nil else { return }

        let identifier = identifier(forJobId: jobId)
        // Recorded before the submit, because the registration inside it is what
        // must never happen twice, whether or not the submit then went through.
        usedIdentifiers.insert(identifier)
        active[jobId] = ActiveTask(
            identifier: identifier,
            title: title,
            subtitle: subtitle,
            totalBytes: max(0, totalBytes ?? 0),
            completedBytes: 0,
            handle: nil
        )

        guard requestActivity(jobId: jobId, identifier: identifier, title: title, subtitle: subtitle) else {
            // Simulator, background refresh switched off, too many pending
            // requests, or a system too busy to start it right away. None of that
            // concerns the download, so the entry goes and the user is told
            // nothing.
            active[jobId] = nil
            logger.info("No live activity for download job \(jobId), the scheduler refused the request")
            return
        }

        logger.debug("Live activity requested for download job \(jobId) as \(identifier)")
    }

    func update(jobId: UUID, completedBytes: Int64, totalBytes: Int64?, subtitle: String?) {
        guard var task = active[jobId] else { return }

        let subtitleOnScreen = task.subtitle
        task.record(completedBytes: completedBytes, totalBytes: totalBytes, subtitle: subtitle)
        active[jobId] = task

        guard let handle = task.handle else { return }
        handle.totalUnitCount = task.totalBytes
        handle.completedUnitCount = task.completedBytes
        // Only on a real change: the title has to be sent along with the
        // subtitle, so an unconditional call would rewrite both several times a
        // second for nothing.
        if task.subtitle != subtitleOnScreen {
            handle.updateTitle(task.title, subtitle: task.subtitle)
        }
    }

    func finish(jobId: UUID, success: Bool) {
        guard let task = active.removeValue(forKey: jobId) else { return }

        guard let handle = task.handle else {
            // Never got runtime, so there is nothing to complete, only a request
            // to take back before the system starts it after the fact.
            scheduler.cancelPendingRequest(identifier: task.identifier)
            return
        }

        if success {
            // Leaves the bar full instead of frozen wherever the last progress
            // report happened to land.
            handle.totalUnitCount = max(task.totalBytes, task.completedBytes)
            handle.completedUnitCount = handle.totalUnitCount
        }
        // Dropped first: the system clears it once the task is completed, and
        // holding a task in a handler that refers back to it is the retain cycle
        // the header warns about.
        handle.setExpirationHandler(nil)
        handle.setCompleted(success: success)
    }

    // MARK: - Identifiers

    /// `<bundle id>.download.<job uuid>`, with a counter appended when that
    /// identifier was already registered in this process.
    ///
    /// The job's UUID is the suffix because it is what the rest of the download
    /// layer keys on, `DownloadTaskKey` included, so an identifier in a log line
    /// points straight at a job, and two downloads running at once stay apart. A
    /// UUID string is hex and hyphens only, so the suffix can never introduce a
    /// dot of its own and stays the single segment the wildcard is assumed to
    /// cover.
    private func identifier(forJobId jobId: UUID) -> String {
        let base = "\(identifierPrefix).\(jobId.uuidString)"
        guard usedIdentifiers.contains(base) else { return base }

        var attempt = 2
        while usedIdentifiers.contains("\(base)-\(attempt)") {
            attempt += 1
        }
        return "\(base)-\(attempt)"
    }

    // MARK: - Scheduler

    /// Asks for the activity and routes the system's answer back to `jobId`.
    private func requestActivity(
        jobId: UUID,
        identifier: String,
        title: String,
        subtitle: String
    ) -> Bool {
        scheduler.submit(
            identifier: identifier,
            title: title,
            subtitle: subtitle
        ) { [weak self] handle in
            self?.taskLaunched(jobId: jobId, identifier: identifier, handle: handle)
        }
    }

    private func taskLaunched(jobId: UUID, identifier: String, handle: PContinuedProcessingTaskHandle) {
        // The download can have finished between the submit and the system
        // getting round to the task. Nothing left to show, and the runtime has
        // to go back right away.
        guard var task = active[jobId], task.identifier == identifier else {
            handle.setCompleted(success: true)
            return
        }

        task.handle = handle
        active[jobId] = task

        handle.setExpirationHandler { [weak self] in
            self?.taskExpired(jobId: jobId, identifier: identifier)
        }
        handle.totalUnitCount = task.totalBytes
        handle.completedUnitCount = task.completedBytes
        handle.updateTitle(task.title, subtitle: task.subtitle)
    }

    private func taskExpired(jobId: UUID, identifier: String) {
        guard let task = active[jobId], task.identifier == identifier else { return }
        active[jobId] = nil

        // Only the activity is over. The transfer belongs to a background
        // URLSession that the system keeps going on its own, so there is
        // deliberately no cancel here.
        task.handle?.setCompleted(success: false)
        logger.info("Live activity for download job \(jobId) was expired by the system")
    }
}

// MARK: - BGTaskScheduler backed scheduler

/// The real thing: `BGTaskScheduler` on iOS 26 and later, a no-op before that.
@MainActor
final class BGContinuedProcessingScheduler: PContinuedProcessingScheduler {

    private let logger = Logger.data

    var isSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    func submit(
        identifier: String,
        title: String,
        subtitle: String,
        launchHandler: @escaping @MainActor (PContinuedProcessingTaskHandle) -> Void
    ) -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        guard register(identifier: identifier, launchHandler: launchHandler) else { return false }
        return submitRequest(identifier: identifier, title: title, subtitle: subtitle)
    }

    func cancelPendingRequest(identifier: String) {
        // Cancelling is as old as the scheduler itself, so this needs no
        // availability check. An identifier that was never submitted, which is
        // every identifier before iOS 26, is simply not found.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    @available(iOS 26.0, *)
    private func register(
        identifier: String,
        launchHandler: @escaping @MainActor (PContinuedProcessingTaskHandle) -> Void
    ) -> Bool {
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            // The main queue, so the handler can reach the controller's state
            // without a hop. The task has to be wired up before the handler
            // returns, an async detour would hand the system a task nobody has
            // set an expiration handler on yet.
            using: .main
        ) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else {
                    // Cannot happen for an identifier submitted as a continued
                    // processing request, but the runtime hands over the base
                    // class, so give the runtime back rather than guess.
                    task.setTaskCompleted(success: false)
                    return
                }
                launchHandler(BGContinuedProcessingTaskHandle(task: task))
            }
        }
        guard registered else {
            // The identifier is not covered by BGTaskSchedulerPermittedIdentifiers.
            logger.warning("BGTaskScheduler refused to register \(identifier)")
            return false
        }
        return true
    }

    @available(iOS 26.0, *)
    private func submitRequest(identifier: String, title: String, subtitle: String) -> Bool {
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: title,
            subtitle: subtitle
        )
        // Fail rather than queue: a queued request can be granted runtime long
        // after the download it was meant to show is over, which would put an
        // activity on screen for nothing. The price is no activity at all on a
        // busy system, which is the harmless direction.
        request.strategy = .fail
        // `requiredResources` stays at its default: GPU access needs an
        // entitlement the app does not have and would get the request rejected.

        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch let error as BGTaskScheduler.Error {
            // `.unavailable` is what the simulator always answers, `.notPermitted`
            // is the user having switched background activity off. Both are
            // expected and neither is the user's problem.
            logger.info("BGTaskScheduler declined \(identifier): code \(error.code.rawValue)")
            return false
        } catch {
            logger.warning("BGTaskScheduler declined \(identifier): \(error)")
            return false
        }
    }
}

/// Wraps the system's task so the controller never sees `BackgroundTasks`.
@available(iOS 26.0, *)
@MainActor
final class BGContinuedProcessingTaskHandle: PContinuedProcessingTaskHandle {

    private let task: BGContinuedProcessingTask

    init(task: BGContinuedProcessingTask) {
        self.task = task
    }

    var totalUnitCount: Int64 {
        get { task.progress.totalUnitCount }
        set { task.progress.totalUnitCount = newValue }
    }

    var completedUnitCount: Int64 {
        get { task.progress.completedUnitCount }
        set { task.progress.completedUnitCount = newValue }
    }

    func updateTitle(_ title: String, subtitle: String) {
        task.updateTitle(title, subtitle: subtitle)
    }

    func setExpirationHandler(_ handler: (() -> Void)?) {
        task.expirationHandler = handler
    }

    func setCompleted(success: Bool) {
        task.setTaskCompleted(success: success)
    }
}
