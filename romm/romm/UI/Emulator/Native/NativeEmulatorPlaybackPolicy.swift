#if !APP_STORE
import Foundation

nonisolated struct NativeEmulatorPlaybackPolicy {
    enum PauseReason: Hashable {
        case inactiveScene
        case menu
        case manual
        case cover
        case restoringState
    }

    private var pauseReasons: Set<PauseReason> = []

    var shouldRun: Bool { pauseReasons.isEmpty }

    mutating func setPaused(_ paused: Bool, for reason: PauseReason) {
        if paused {
            pauseReasons.insert(reason)
        } else {
            pauseReasons.remove(reason)
        }
    }
}

// Delta asks its resume delegate from its emulation queue as well as the main queue.
nonisolated final class NativeEmulatorResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = false

    var isAllowed: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return allowed
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            allowed = newValue
        }
    }
}
#endif
