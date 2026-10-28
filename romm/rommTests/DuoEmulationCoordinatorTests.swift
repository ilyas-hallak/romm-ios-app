#if !APP_STORE
import Foundation
import Testing
import DeltaCore
import MelonDSDeltaCore
@testable import romm

@MainActor
struct DuoEmulationCoordinatorTests {
    @Test func openingBeforeTheGracePeriodCancelsTheCoverPause() {
        let harness = Harness()
        harness.close()
        #expect(harness.lidInputs == [true])
        #expect(harness.policy.shouldRun)
        #expect(harness.scheduler.jobs.map(\.delay) == [1])

        harness.open()
        #expect(harness.scheduler.jobs[0].isCancelled)
        harness.scheduler.deliver(0)

        #expect(harness.lidInputs == [true, false])
        #expect(harness.pauseRequests == [false])
        #expect(harness.policy.shouldRun)
    }

    @Test func repeatedCloseDoesNotRestartTheGracePeriod() {
        let harness = Harness()
        harness.close()
        harness.close()

        #expect(harness.scheduler.jobs.count == 1)
        #expect(!harness.scheduler.jobs[0].isCancelled)
        #expect(harness.lidInputs == [true])

        harness.scheduler.deliver(0)
        harness.close()

        #expect(harness.scheduler.jobs.count == 1)
        #expect(harness.pauseRequests == [true])
        #expect(!harness.policy.shouldRun)
    }

    @Test func anOldCallbackCannotPauseANewlyClosedCover() {
        let harness = Harness()
        harness.close()
        harness.open()
        harness.close()
        #expect(harness.scheduler.jobs.count == 2)

        // Simulate a cancelled callback that was already queued for delivery.
        harness.scheduler.deliver(0)
        #expect(harness.policy.shouldRun)
        #expect(harness.pauseRequests == [false])

        harness.scheduler.deliver(1)
        #expect(!harness.policy.shouldRun)
        #expect(harness.pauseRequests == [false, true])
    }

    @Test func stoppingCancelsPendingWorkAndReleasesTheDSLid() {
        let harness = Harness()
        harness.close()
        harness.coordinator.stop()
        harness.scheduler.deliver(0)
        harness.close()

        #expect(harness.scheduler.jobs[0].isCancelled)
        #expect(harness.scheduler.jobs.count == 1)
        #expect(harness.lidInputs == [true, false])
        #expect(harness.pauseRequests.isEmpty)
    }

    @Test(arguments: [NativeEmulatorPlaybackPolicy.PauseReason.menu, .manual,
                      .inactiveScene, .restoringState])
    func openingOnlyReleasesTheCoverPause(reason: NativeEmulatorPlaybackPolicy.PauseReason) {
        let harness = Harness()
        harness.close()
        harness.setPaused(true, for: reason)
        harness.scheduler.deliver(0)
        harness.open()

        #expect(!harness.policy.shouldRun)
        harness.setPaused(false, for: reason)
        #expect(harness.policy.shouldRun)
    }

    @Test func aCoveredSessionWaitsForOpeningBeforeItCanLaunch() {
        let harness = Harness()
        harness.sessionRunning = false
        harness.coreRunning = false
        harness.close()

        #expect(harness.scheduler.jobs.isEmpty)
        #expect(harness.lidInputs.isEmpty)
        #expect(!harness.policy.shouldRun)

        harness.open()
        #expect(harness.policy.shouldRun)
        harness.sessionRunning = true
        harness.coreRunning = true
        harness.coordinator.applyLidState()
        #expect(harness.lidInputs == [false])
    }

    @Test func closingAnAlreadyPausedDSImmediatelyClaimsTheCoverPause() {
        let harness = Harness()
        harness.setPaused(true, for: .menu)
        harness.close()

        #expect(harness.scheduler.jobs.isEmpty)
        #expect(harness.pauseRequests == [true])
        harness.open()
        #expect(!harness.policy.shouldRun)
        harness.setPaused(false, for: .menu)
        #expect(harness.policy.shouldRun)
    }

    @Test func lidInputDoesNotDependOnCoverArtwork() {
        let harness = Harness()
        harness.coordinator.setLidClosed(true)
        #expect(harness.lidInputs == [true])
        #expect(harness.pauseRequests.isEmpty)
        #expect(harness.scheduler.jobs.isEmpty)
    }

    @Test(arguments: ["gba", "gbc", "n64"])
    func otherCoresPauseImmediatelyWithoutReceivingDSLidInput(coreName: String) {
        let harness = Harness(gameType: GameType("com.rileytestut.delta.game.\(coreName)"))
        harness.close()
        #expect(!harness.policy.shouldRun)
        #expect(harness.scheduler.jobs.isEmpty)
        harness.open()
        harness.coordinator.stop()

        #expect(harness.policy.shouldRun)
        #expect(harness.pauseRequests == [true, false])
        #expect(harness.lidInputs.isEmpty)
    }
}

@MainActor
private final class Harness {
    var sessionRunning = true
    var coreRunning = true
    var policy = NativeEmulatorPlaybackPolicy()
    var lidInputs = [Bool]()
    var pauseRequests = [Bool]()
    let scheduler = ManualScheduler()
    let gameType: GameType

    lazy var coordinator = DuoEmulationCoordinator(
        gameType: gameType,
        isSessionRunning: { [weak self] in self?.sessionRunning == true },
        isCoreRunning: { [weak self] in self?.coreRunning == true },
        sendLidInput: { [weak self] closed in
            guard let self, self.sessionRunning else { return }
            self.lidInputs.append(closed)
        },
        setCoverPaused: { [weak self] paused in
            self?.pauseRequests.append(paused)
            self?.setPaused(paused, for: .cover)
        },
        schedule: { [weak self] delay, action in
            self?.scheduler.schedule(after: delay, action: action) ?? {}
        }
    )

    init(gameType: GameType = .ds) {
        self.gameType = gameType
    }

    func close() {
        coordinator.setLidClosed(true)
        coordinator.setCovered(true)
    }

    func open() {
        coordinator.setLidClosed(false)
        coordinator.setCovered(false)
    }

    func setPaused(_ paused: Bool, for reason: NativeEmulatorPlaybackPolicy.PauseReason) {
        policy.setPaused(paused, for: reason)
        coreRunning = sessionRunning && policy.shouldRun
    }
}

@MainActor
private final class ManualScheduler {
    final class Job {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false

        init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.action = action
        }
    }

    private(set) var jobs = [Job]()

    func schedule(after delay: TimeInterval,
                  action: @escaping @MainActor () -> Void) -> DuoEmulationCoordinator.Cancel {
        let job = Job(delay: delay, action: action)
        jobs.append(job)
        return { job.isCancelled = true }
    }

    func deliver(_ index: Int) {
        jobs[index].action()
    }
}
#endif
