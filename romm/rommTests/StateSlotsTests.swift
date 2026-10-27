import Testing
import Foundation
@testable import romm

struct StateSlotsTests {

    private func candidate(id: Int, fileName: String, updatedAt: Date) -> StateSlots.Candidate {
        StateSlots.Candidate(id: id, fileName: fileName, updatedAt: updatedAt)
    }

    // MARK: - Real slots

    @Test func recognisableSlotNameKeepsItsRealSlot() {
        let candidates = [candidate(id: 1, fileName: "slot3.state", updatedAt: Date())]
        let (slotByStateId, overflow) = StateSlots.assign(candidates)

        #expect(slotByStateId[1] == 3)
        #expect(overflow == 0)
    }

    // MARK: - Unnamed states get free slots without colliding

    @Test func unnamedStatesGetFreeSlotsWithoutCollidingWithRealOnes() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let candidates = [
            candidate(id: 1, fileName: "slot0.state", updatedAt: base),
            candidate(id: 2, fileName: "Chrono Trigger (USA).state", updatedAt: base.addingTimeInterval(1)),
            candidate(id: 3, fileName: "Chrono Trigger (USA) [2].state", updatedAt: base.addingTimeInterval(2))
        ]
        let (slotByStateId, overflow) = StateSlots.assign(candidates)

        #expect(slotByStateId[1] == 0)
        // Slot 0 is taken, so the unnamed states start from slot 1.
        #expect(slotByStateId[2] == 1)
        #expect(slotByStateId[3] == 2)
        #expect(overflow == 0)
    }

    // MARK: - Deterministic ordering

    @Test func assignmentIsDeterministicRegardlessOfInputOrder() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let a = candidate(id: 10, fileName: "a.state", updatedAt: base)
        let b = candidate(id: 20, fileName: "b.state", updatedAt: base.addingTimeInterval(10))
        let c = candidate(id: 30, fileName: "c.state", updatedAt: base.addingTimeInterval(20))

        let (forward, _) = StateSlots.assign([a, b, c])
        let (shuffled, _) = StateSlots.assign([c, a, b])

        #expect(forward == shuffled)
    }

    @Test func tiedUpdatedAtBreaksTiesById() {
        let same = Date(timeIntervalSince1970: 1_700_000_000)
        // Same updatedAt, so ordering must fall back to id.
        let higherId = candidate(id: 2, fileName: "second.state", updatedAt: same)
        let lowerId = candidate(id: 1, fileName: "first.state", updatedAt: same)

        let (slotByStateId, _) = StateSlots.assign([higherId, lowerId])

        #expect(slotByStateId[1] == 0)
        #expect(slotByStateId[2] == 1)
    }

    // MARK: - Overflow beyond maxSlot

    @Test func overflowCountsCandidatesBeyondMaxSlot() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // maxSlot is 20, so slots 0...20 (21 total) are available. 23 unnamed
        // candidates should fill all 21 and leave 2 unassigned.
        let candidates = (0..<23).map {
            candidate(id: $0, fileName: "Unnamed \($0).state", updatedAt: base.addingTimeInterval(Double($0)))
        }
        let (slotByStateId, overflow) = StateSlots.assign(candidates)

        #expect(slotByStateId.count == 21)
        #expect(overflow == 2)
        // The earliest-updated candidates win the available slots.
        #expect(slotByStateId[0] == 0)
        #expect(slotByStateId[20] == 20)
        #expect(slotByStateId[21] == nil)
        #expect(slotByStateId[22] == nil)
    }

    // MARK: - fileName / slot(fromFileName:) are inverse

    @Test func fileNameAndSlotFromFileNameAreInverse() throws {
        for slot in [0, 1, 7, 20] {
            let fileName = StateSlots.fileName(slot: slot)
            let parsed = try #require(StateSlots.slot(fromFileName: fileName))
            #expect(parsed == slot)
        }
    }

    @Test func slotFromFileNameReturnsNilForAnUnrecognisableName() {
        #expect(StateSlots.slot(fromFileName: "Chrono Trigger (USA).state") == nil)
    }
}
