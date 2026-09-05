import Testing
import Foundation
@testable import romm

struct LocalSaveStoreRepositoryTests {

    private func makeStore() -> (LocalSaveStoreRepository, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSaveStoreRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (LocalSaveStoreRepository(rootDirectory: tmp), tmp)
    }

    @Test func batteryRoundtrip() throws {
        let (store, _) = makeStore()
        let payload = Data([0xCA, 0xFE])
        try store.writeBattery(romId: 42, data: payload)
        #expect(try store.readBattery(romId: 42) == payload)
    }

    @Test func batteryReturnsNilWhenMissing() throws {
        let (store, _) = makeStore()
        #expect(try store.readBattery(romId: 99) == nil)
    }

    /// Sync negotiation reports the whole library in one request, so the store
    /// has to be able to name every ROM it holds something for.
    @Test func listsEveryRomItHoldsSomethingFor() throws {
        let (store, _) = makeStore()
        try store.writeBattery(romId: 42, data: Data([0xCA]))
        try store.writeState(romId: 7, slot: 0, data: Data([0x01]))
        #expect(try store.listRomIds() == [7, 42])
    }

    @Test func listsNothingForAnEmptyStore() throws {
        let (store, _) = makeStore()
        #expect(try store.listRomIds().isEmpty)
    }

    /// The root is shared with whatever else may end up there, and a stray
    /// directory must not become a ROM id.
    @Test func skipsDirectoriesThatAreNotRomIds() throws {
        let (store, root) = makeStore()
        try store.writeBattery(romId: 3, data: Data([0xCA]))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-rom", isDirectory: true),
            withIntermediateDirectories: true
        )
        #expect(try store.listRomIds() == [3])
    }

    @Test func stateRoundtripAndList() throws {
        let (store, _) = makeStore()
        try store.writeState(romId: 1, slot: 1, data: Data([0x01]))
        try store.writeState(romId: 1, slot: 2, data: Data([0x02]))
        let entries = try store.listStates(romId: 1)
        #expect(entries.map(\.slot).sorted() == [1, 2])
        #expect(try store.readState(romId: 1, slot: 1) == Data([0x01]))
    }

    @Test func deleteState() throws {
        let (store, _) = makeStore()
        try store.writeState(romId: 1, slot: 1, data: Data([0x01]))
        try store.deleteState(romId: 1, slot: 1)
        #expect(try store.readState(romId: 1, slot: 1) == nil)
    }

    /// Regression: PR #57 changed the UI default slot from 1 to 0. Slot 0 must
    /// be a valid, independently addressable slot — write/read/list must all work.
    @Test func slotZeroIsAddressableIndependentlyFromSlotOne() throws {
        let (store, _) = makeStore()
        let data0 = Data([0xAA])
        let data1 = Data([0xBB])
        try store.writeState(romId: 5, slot: 0, data: data0)
        try store.writeState(romId: 5, slot: 1, data: data1)
        #expect(try store.readState(romId: 5, slot: 0) == data0)
        #expect(try store.readState(romId: 5, slot: 1) == data1)
        let slots = try store.listStates(romId: 5).map(\.slot).sorted()
        #expect(slots == [0, 1])
    }

    /// Regression: states saved under the old 1-based default (slot 1) remain
    /// readable after the switch to 0-based slots — slot 1 on disk is still slot 1.
    @Test func prePRSlotOneStatesRemainReadableAtSlotOne() throws {
        let (store, _) = makeStore()
        let legacyData = Data([0xDE, 0xAD])
        // Simulate a state written by the old 1-based UI (default slot 1).
        try store.writeState(romId: 7, slot: 1, data: legacyData)
        #expect(try store.readState(romId: 7, slot: 0) == nil, "slot 0 must be empty")
        #expect(try store.readState(romId: 7, slot: 1) == legacyData, "legacy slot 1 must still be readable")
    }
}
