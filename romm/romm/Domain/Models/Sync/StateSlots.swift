import Foundation

/// Maps save states between their on-disk slot index and the server's
/// filename convention, shared by every sync path so a server state keeps
/// landing in the same slot no matter which path put it there.
enum StateSlots {

    static func fileName(slot: Int) -> String { "slot\(slot).state" }

    /// Parses `slotN.state` (or `slotN.*`) back to slot index `N`.
    static func slot(fromFileName name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("slot") else { return nil }
        return Int(stem.dropFirst("slot".count))
    }

    /// A server state, reduced to what the slot assignment needs.
    struct Candidate {
        let id: Int
        let fileName: String
        let updatedAt: Date
    }

    /// Maps server states onto local slots: a recognisable `slotN.state` name
    /// keeps its real slot, anything else gets the next free slot in a
    /// deterministic order so the same server state keeps landing in the same
    /// slot across runs. `overflow` counts the states that found no free slot.
    static func assign(_ candidates: [Candidate]) -> (slotByStateId: [Int: Int], overflow: Int) {
        // First pass: map states with a recognizable `slotN.state` name to
        // their real slot. States with any other server-side name (e.g.
        // "Chrono Trigger (USA) [2026-05-06 ...].state") are collected so we
        // can assign them synthetic slots that never collide with real ones.
        var realSlots = Set<Int>()
        var unnamed: [Candidate] = []
        for c in candidates {
            if let slot = slot(fromFileName: c.fileName) {
                realSlots.insert(slot)
            } else {
                unnamed.append(c)
            }
        }

        // Deterministically order the unnamed states (by updatedAt, then id)
        // so the same server state maps to the same synthetic slot across
        // launches, then hand each the next free slot index.
        let ordered = unnamed.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt < $1.updatedAt
        }
        // Cap at the highest slot the UI can display (slots 0…20 = 21 total,
        // see EmulatorMenuSheet). Anything beyond that has no visible slot.
        let maxSlot = 20
        var syntheticSlotByStateId: [Int: Int] = [:]
        var nextSlot = 0
        var overflow = 0
        for c in ordered {
            while realSlots.contains(nextSlot) { nextSlot += 1 }
            guard nextSlot <= maxSlot else { overflow += 1; continue }
            syntheticSlotByStateId[c.id] = nextSlot
            realSlots.insert(nextSlot)
        }

        var slotByStateId: [Int: Int] = [:]
        for c in candidates {
            guard let slot = slot(fromFileName: c.fileName) ?? syntheticSlotByStateId[c.id] else { continue }
            slotByStateId[c.id] = slot
        }
        return (slotByStateId, overflow)
    }
}
