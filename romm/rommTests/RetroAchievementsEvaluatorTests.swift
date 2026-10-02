import Foundation
import Testing
@testable import romm

struct RetroAchievementsEvaluatorTests {
    @Test func triggersWhenTheMemoryConditionBecomesTrue() {
        let memory = TestMemory(bytes: [0])
        let evaluator = RetroAchievementsEvaluator(memory: memory)

        #expect(evaluator.activate(achievementID: 42, definition: "0xH0000=1"))
        #expect(evaluator.evaluateFrame().isEmpty)

        memory.bytes = Data([1])
        #expect(evaluator.evaluateFrame() == [42])
        #expect(evaluator.evaluateFrame().isEmpty)
    }

    @Test func rejectsInvalidAchievementIdentifiers() {
        let evaluator = RetroAchievementsEvaluator(memory: TestMemory(bytes: [0]))

        #expect(!evaluator.activate(achievementID: -1, definition: "0xH0000=1"))
    }
}

private final class TestMemory: PAchievementMemoryProvider {
    var bytes: Data

    init(bytes: [UInt8]) {
        self.bytes = Data(bytes)
    }

    func readMemory(address: UInt32, length: Int) -> Data? {
        let offset = Int(address)
        guard offset >= 0, offset <= bytes.count, length <= bytes.count - offset else {
            return nil
        }
        return bytes.subdata(in: offset..<(offset + length))
    }
}
