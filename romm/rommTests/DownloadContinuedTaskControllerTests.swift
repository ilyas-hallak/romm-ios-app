//
//  DownloadContinuedTaskControllerTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

/// `BGTaskScheduler` cannot be driven from a unit test, and a
/// `BGContinuedProcessingTask` cannot be built at all, so everything here runs
/// against the controller's own seam. What is tested is the part that belongs to
/// the app: identifier shape, several jobs at once, the progress numbers, and
/// that every path ends the task exactly once.
///
/// The suite is explicitly main actor bound because the test target does not
/// default to main actor isolation the way the app target does.
@MainActor
struct DownloadContinuedTaskControllerTests {

    private static let prefix = "com.romm.app.test.download"

    private func makeController(
        scheduler: FakeContinuedProcessingScheduler
    ) -> DownloadContinuedTaskController {
        DownloadContinuedTaskController(scheduler: scheduler, identifierPrefix: Self.prefix)
    }

    // MARK: - Identifiers

    @Test func identifierIsTheJobIdUnderTheDownloadPrefix() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1024)

        // Has to stay a single segment after the prefix, that is all the
        // Info.plist wildcard is assumed to cover.
        #expect(scheduler.submittedIdentifiers == ["\(Self.prefix).\(jobId.uuidString)"])
    }

    @Test func parallelJobsGetSeparateIdentifiers() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let first = UUID()
        let second = UUID()

        controller.start(jobId: first, title: "First", subtitle: "Starting", totalBytes: 100)
        controller.start(jobId: second, title: "Second", subtitle: "Starting", totalBytes: 200)

        #expect(scheduler.submittedIdentifiers.count == 2)
        #expect(Set(scheduler.submittedIdentifiers).count == 2)
        #expect(scheduler.submissions.map(\.title) == ["First", "Second"])
    }

    @Test func startingTheSameJobTwiceSubmitsOnce() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 100)
        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 100)

        #expect(scheduler.submittedIdentifiers.count == 1)
    }

    @Test func aJobStartedAgainAfterFinishingGetsAFreshIdentifier() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()
        let base = "\(Self.prefix).\(jobId.uuidString)"

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 100)
        scheduler.launch(identifier: base)
        controller.finish(jobId: jobId, success: false)

        // A restarted download must not reuse the identifier: a second
        // registration of the same one kills the app.
        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Retrying", totalBytes: 100)

        #expect(scheduler.submittedIdentifiers == [base, "\(base)-2"])
    }

    // MARK: - Unavailable or refused scheduler

    @Test func startDoesNothingWhenContinuedTasksAreUnsupported() {
        let scheduler = FakeContinuedProcessingScheduler()
        scheduler.isSupported = false
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 100)
        controller.update(jobId: jobId, completedBytes: 50, totalBytes: 100, subtitle: "Half way")
        controller.finish(jobId: jobId, success: true)

        #expect(scheduler.submissions.isEmpty)
        #expect(scheduler.cancelledIdentifiers.isEmpty)
    }

    @Test func aRefusedSubmitLeavesNothingBehind() {
        // What the simulator does: the submit throws `.unavailable`.
        let scheduler = FakeContinuedProcessingScheduler()
        scheduler.submitSucceeds = false
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 100)
        controller.update(jobId: jobId, completedBytes: 50, totalBytes: 100, subtitle: "Half way")
        controller.finish(jobId: jobId, success: true)

        #expect(scheduler.submittedIdentifiers.count == 1)
        // No task ever existed, so nothing is cancelled and nothing is completed.
        #expect(scheduler.cancelledIdentifiers.isEmpty)
    }

    // MARK: - Progress

    @Test func launchingTheTaskWritesTitleAndProgressStraightOntoIt() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 2048)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")

        #expect(handle?.totalUnitCount == 2048)
        #expect(handle?.completedUnitCount == 0)
        #expect(handle?.titleUpdates.map(\.subtitle) == ["Starting"])
        #expect(handle?.expirationHandlerIsSet == true)
    }

    @Test func updateMovesTheProgressOfTheRightJobOnly() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let first = UUID()
        let second = UUID()

        controller.start(jobId: first, title: "First", subtitle: "Starting", totalBytes: 1000)
        controller.start(jobId: second, title: "Second", subtitle: "Starting", totalBytes: 4000)
        let firstHandle = scheduler.launch(identifier: "\(Self.prefix).\(first.uuidString)")
        let secondHandle = scheduler.launch(identifier: "\(Self.prefix).\(second.uuidString)")

        controller.update(jobId: first, completedBytes: 250, totalBytes: 1000, subtitle: nil)

        #expect(firstHandle?.completedUnitCount == 250)
        #expect(firstHandle?.totalUnitCount == 1000)
        #expect(secondHandle?.completedUnitCount == 0)
        #expect(secondHandle?.totalUnitCount == 4000)
    }

    @Test func progressReportedBeforeTheTaskLaunchesIsAppliedWhenItDoes() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: nil)
        controller.update(jobId: jobId, completedBytes: 400, totalBytes: 1000, subtitle: "Downloading")

        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")

        #expect(handle?.totalUnitCount == 1000)
        #expect(handle?.completedUnitCount == 400)
        #expect(handle?.titleUpdates.map(\.subtitle) == ["Downloading"])
    }

    @Test func anUnknownTotalStaysAtZeroUntilUpdateSuppliesOne() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: nil)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")
        #expect(handle?.totalUnitCount == 0)

        controller.update(jobId: jobId, completedBytes: 10, totalBytes: nil, subtitle: nil)
        // Nothing announced a size, so the only honest total is the bytes that
        // have already arrived.
        #expect(handle?.totalUnitCount == 10)
        #expect(handle?.completedUnitCount == 10)

        controller.update(jobId: jobId, completedBytes: 20, totalBytes: 900, subtitle: nil)
        #expect(handle?.totalUnitCount == 900)
        #expect(handle?.completedUnitCount == 20)
    }

    @Test func theTotalGrowsWhenMoreBytesArriveThanWereAnnounced() {
        // Real case: the server builds archives while it serves them, so the
        // announced size is only a hint.
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")

        controller.update(jobId: jobId, completedBytes: 1400, totalBytes: 1000, subtitle: nil)

        #expect(handle?.totalUnitCount == 1400)
        #expect(handle?.completedUnitCount == 1400)
    }

    @Test func negativeByteCountsAreIgnored() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: -1)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")
        #expect(handle?.totalUnitCount == 0)

        controller.update(jobId: jobId, completedBytes: -5, totalBytes: 100, subtitle: nil)
        #expect(handle?.completedUnitCount == 0)
        #expect(handle?.totalUnitCount == 100)
    }

    @Test func theSubtitleIsOnlyRewrittenWhenItChanges() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")

        controller.update(jobId: jobId, completedBytes: 100, totalBytes: 1000, subtitle: "Starting")
        controller.update(jobId: jobId, completedBytes: 200, totalBytes: 1000, subtitle: nil)
        controller.update(jobId: jobId, completedBytes: 300, totalBytes: 1000, subtitle: "1.2 MB/s")
        controller.update(jobId: jobId, completedBytes: 400, totalBytes: 1000, subtitle: "1.2 MB/s")

        // Progress comes in ten times a second, the text almost never changes,
        // and the title always has to be sent along with it.
        #expect(handle?.titleUpdates.map(\.subtitle) == ["Starting", "1.2 MB/s"])
        #expect(handle?.titleUpdates.allSatisfy { $0.title == "Pokemon Red" } == true)
    }

    @Test func updateForAnUnknownJobDoesNothing() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.update(jobId: UUID(), completedBytes: 100, totalBytes: 200, subtitle: "Downloading")

        #expect(scheduler.submissions.isEmpty)
    }

    // MARK: - Finishing

    @Test func aSuccessfulFinishFillsTheBarAndCompletesTheTaskOnce() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")
        controller.update(jobId: jobId, completedBytes: 600, totalBytes: 1000, subtitle: nil)

        controller.finish(jobId: jobId, success: true)

        #expect(handle?.completedUnitCount == 1000)
        #expect(handle?.totalUnitCount == 1000)
        #expect(handle?.completions == [true])
        // Cleared before completing, so the task is not held by its own handler.
        #expect(handle?.expirationHandlerIsSet == false)
    }

    @Test func aFailedFinishCompletesTheTaskWithoutFillingTheBar() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")
        controller.update(jobId: jobId, completedBytes: 600, totalBytes: 1000, subtitle: nil)

        controller.finish(jobId: jobId, success: false)

        #expect(handle?.completedUnitCount == 600)
        #expect(handle?.completions == [false])
    }

    @Test func finishingTwiceCompletesTheTaskOnlyOnce() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")

        controller.finish(jobId: jobId, success: true)
        controller.finish(jobId: jobId, success: true)
        controller.finish(jobId: jobId, success: false)

        #expect(handle?.completions == [true])
    }

    @Test func finishForAnUnknownJobDoesNothing() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)

        controller.finish(jobId: UUID(), success: true)

        #expect(scheduler.cancelledIdentifiers.isEmpty)
        #expect(scheduler.submissions.isEmpty)
    }

    @Test func finishingBeforeTheTaskLaunchedWithdrawsTheRequest() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()
        let identifier = "\(Self.prefix).\(jobId.uuidString)"

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        controller.finish(jobId: jobId, success: true)

        #expect(scheduler.cancelledIdentifiers == [identifier])
    }

    @Test func aTaskGrantedRuntimeAfterTheJobFinishedGivesItBackAtOnce() {
        // The scheduler can start a task later than the submit, by which time
        // the download may be long done. Nothing to show, so hand the runtime
        // straight back instead of leaving a stale activity up.
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()
        let identifier = "\(Self.prefix).\(jobId.uuidString)"

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        controller.finish(jobId: jobId, success: true)

        let handle = scheduler.launch(identifier: identifier)

        #expect(handle?.completions == [true])
        #expect(handle?.titleUpdates.isEmpty == true)
        #expect(handle?.expirationHandlerIsSet == false)
    }

    // MARK: - Expiration

    @Test func expirationCompletesTheTaskAndForgetsTheJob() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let jobId = UUID()

        controller.start(jobId: jobId, title: "Pokemon Red", subtitle: "Starting", totalBytes: 1000)
        let handle = scheduler.launch(identifier: "\(Self.prefix).\(jobId.uuidString)")

        handle?.expire()

        #expect(handle?.completions == [false])

        // The transfer itself carries on in the background session, so a later
        // finish is only about a task that is already over.
        controller.finish(jobId: jobId, success: true)
        #expect(handle?.completions == [false])
        #expect(scheduler.cancelledIdentifiers.isEmpty)
    }

    @Test func expirationOfOneJobLeavesTheOtherRunning() {
        let scheduler = FakeContinuedProcessingScheduler()
        let controller = makeController(scheduler: scheduler)
        let first = UUID()
        let second = UUID()

        controller.start(jobId: first, title: "First", subtitle: "Starting", totalBytes: 1000)
        controller.start(jobId: second, title: "Second", subtitle: "Starting", totalBytes: 1000)
        let firstHandle = scheduler.launch(identifier: "\(Self.prefix).\(first.uuidString)")
        let secondHandle = scheduler.launch(identifier: "\(Self.prefix).\(second.uuidString)")

        firstHandle?.expire()
        controller.update(jobId: second, completedBytes: 700, totalBytes: 1000, subtitle: nil)
        controller.finish(jobId: second, success: true)

        #expect(firstHandle?.completions == [false])
        #expect(secondHandle?.completions == [true])
        #expect(secondHandle?.completedUnitCount == 1000)
    }
}

// MARK: - Test doubles

/// Stands in for `BGTaskScheduler`, and lets a test decide whether a submit is
/// accepted and when the system supposedly grants the task runtime.
@MainActor
private final class FakeContinuedProcessingScheduler: PContinuedProcessingScheduler {

    var isSupported = true
    /// False stands for every refusal the real scheduler can answer with,
    /// `.unavailable` on the simulator being the common one.
    var submitSucceeds = true

    private(set) var submissions: [(identifier: String, title: String, subtitle: String)] = []
    private(set) var cancelledIdentifiers: [String] = []

    private var launchHandlers: [String: @MainActor (PContinuedProcessingTaskHandle) -> Void] = [:]

    var submittedIdentifiers: [String] {
        submissions.map(\.identifier)
    }

    func submit(
        identifier: String,
        title: String,
        subtitle: String,
        launchHandler: @escaping @MainActor (PContinuedProcessingTaskHandle) -> Void
    ) -> Bool {
        submissions.append((identifier: identifier, title: title, subtitle: subtitle))
        guard submitSucceeds else { return false }
        launchHandlers[identifier] = launchHandler
        return true
    }

    func cancelPendingRequest(identifier: String) {
        cancelledIdentifiers.append(identifier)
    }

    /// Plays the moment the system hands over the task. Returns the handle the
    /// controller was given, or nil when nothing was ever registered under that
    /// identifier.
    @discardableResult
    func launch(identifier: String) -> FakeContinuedProcessingTaskHandle? {
        guard let handler = launchHandlers[identifier] else { return nil }
        let handle = FakeContinuedProcessingTaskHandle()
        handler(handle)
        return handle
    }
}

/// Records everything the controller does to a task, so a test can check the
/// progress numbers and that the task was completed exactly once.
@MainActor
private final class FakeContinuedProcessingTaskHandle: PContinuedProcessingTaskHandle {

    var totalUnitCount: Int64 = 0
    var completedUnitCount: Int64 = 0

    private(set) var titleUpdates: [(title: String, subtitle: String)] = []
    private(set) var completions: [Bool] = []

    private var expirationHandler: (() -> Void)?

    var expirationHandlerIsSet: Bool {
        expirationHandler != nil
    }

    func updateTitle(_ title: String, subtitle: String) {
        titleUpdates.append((title: title, subtitle: subtitle))
    }

    func setExpirationHandler(_ handler: (() -> Void)?) {
        expirationHandler = handler
    }

    func setCompleted(success: Bool) {
        completions.append(success)
    }

    /// Plays the system taking the task's runtime away.
    func expire() {
        let handler = expirationHandler
        // The real task clears the property once it has called the handler.
        expirationHandler = nil
        handler?()
    }
}
