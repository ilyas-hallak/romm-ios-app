import Foundation
import rcheevos

/// Evaluates RetroAchievements trigger definitions against a core's current memory.
final class RetroAchievementsEvaluator {
    private let runtime: UnsafeMutablePointer<rc_runtime_t>
    private let memoryBox: MemoryBox

    init(memory: PAchievementMemoryProvider) {
        runtime = rc_runtime_alloc()
        memoryBox = MemoryBox(memory: memory)
    }

    deinit {
        rc_runtime_destroy(runtime)
    }

    @discardableResult
    func activate(achievementID: Int, definition: String) -> Bool {
        guard let identifier = UInt32(exactly: achievementID) else { return false }
        return definition.withCString {
            rc_runtime_activate_achievement(runtime, identifier, $0, nil, 0) == RC_OK
        }
    }

    func evaluateFrame() -> [Int] {
        triggeredAchievementIDs.removeAll(keepingCapacity: true)
        rc_runtime_do_frame(
            runtime,
            runtimeEventHandler,
            readEmulatedMemory,
            Unmanaged.passUnretained(memoryBox).toOpaque(),
            nil
        )
        return triggeredAchievementIDs.compactMap(Int.init(exactly:))
    }
}

private final class MemoryBox {
    let memory: PAchievementMemoryProvider

    init(memory: PAchievementMemoryProvider) {
        self.memory = memory
    }
}

// rcheevos invokes these synchronously from rc_runtime_do_frame. The evaluator
// is driven from Libretro's main-actor frame callback, so a process-wide buffer
// is sufficient until multiple simultaneous emulator sessions are supported.
nonisolated(unsafe) private var triggeredAchievementIDs: [UInt32] = []

private func runtimeEventHandler(_ event: UnsafePointer<rc_runtime_event_t>?) {
    guard let event,
          event.pointee.type == RC_RUNTIME_EVENT_ACHIEVEMENT_TRIGGERED else {
        return
    }
    triggeredAchievementIDs.append(event.pointee.id)
}

private func readEmulatedMemory(
    address: UInt32,
    length: UInt32,
    context: UnsafeMutableRawPointer?
) -> UInt32 {
    guard let context,
          length > 0,
          length <= 4 else {
        return 0
    }

    let memory = Unmanaged<MemoryBox>.fromOpaque(context).takeUnretainedValue().memory
    guard let bytes = memory.readMemory(address: address, length: Int(length)),
          bytes.count == Int(length) else {
        return 0
    }

    return bytes.enumerated().reduce(0) { value, byte in
        value | UInt32(byte.element) << UInt32(byte.offset * 8)
    }
}
