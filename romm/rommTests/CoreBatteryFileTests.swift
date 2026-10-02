import Testing
import Foundation
@testable import romm

struct CoreBatteryFileTests {

    private let romId = 7
    private let root: URL
    private let store: LocalSaveStoreRepository
    private let file: CoreBatteryFile

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoreBatteryFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = LocalSaveStoreRepository(rootDirectory: root.appendingPathComponent("Store"))
        file = CoreBatteryFile(
            url: root.appendingPathComponent("Roms/Game.dsv"),
            romId: romId,
            saveStates: EmulatorSaveStatesUseCase(saveStore: store)
        )
    }

    private func writeCoreFile(_ data: Data, modifiedAt date: Date) throws {
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file.url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.url.path)
    }

    private func writeStore(_ data: Data, modifiedAt date: Date) throws {
        try store.writeBattery(romId: romId, data: data)
        try store.setBatteryModifiedAt(romId: romId, date: date)
    }

    private var coreFileData: Data? { try? Data(contentsOf: file.url) }

    // MARK: - Stage

    @Test func stageLeavesTheCoreAloneWhenNothingIsStored() throws {
        try writeCoreFile(Data([0x01]), modifiedAt: Date())

        #expect(file.stage() == .nothingStored)
        #expect(coreFileData == Data([0x01]))
    }

    @Test func stageCopiesTheStoreWhenTheCoreHasNoFile() throws {
        try writeStore(Data([0x0A]), modifiedAt: Date())

        #expect(file.stage() == .staged)
        #expect(coreFileData == Data([0x0A]))
    }

    /// Issue #189: the game saved, the core wrote its file, and the app was
    /// swiped away before the store caught up.
    @Test func stageKeepsANewerCoreFileAndAdoptsIt() throws {
        let now = Date()
        try writeStore(Data([0x0A]), modifiedAt: now.addingTimeInterval(-600))
        try writeCoreFile(Data([0x0B]), modifiedAt: now)

        #expect(file.stage() == .adoptedCoreFile(Data([0x0B])))
        #expect(coreFileData == Data([0x0B]))
        #expect(try store.readBattery(romId: romId) == Data([0x0B]))
    }

    /// A save pulled from the server, or one restored on purpose, is newer
    /// than what the core has lying around and has to win.
    @Test func stageOverwritesAnOlderCoreFile() throws {
        let now = Date()
        try writeCoreFile(Data([0x0B]), modifiedAt: now.addingTimeInterval(-600))
        try writeStore(Data([0x0A]), modifiedAt: now)

        #expect(file.stage() == .staged)
        #expect(coreFileData == Data([0x0A]))
    }

    @Test func stageHandsTheCoreTheAdaptedBytes() throws {
        try writeStore(Data([0x0A, 0x0A, 0x0A]), modifiedAt: Date())

        #expect(file.stage(adapt: { $0.prefix(1) }) == .staged)
        #expect(coreFileData == Data([0x0A]))
    }

    /// The core's file is the adapted copy of the store, which is not news
    /// even though the core's file is the newer one.
    @Test func stageDoesNotAdoptACoreFileThatMatchesTheAdaptedStore() throws {
        let now = Date()
        try writeStore(Data([0x0A, 0x0A]), modifiedAt: now.addingTimeInterval(-600))
        try writeCoreFile(Data([0x0A]), modifiedAt: now)

        #expect(file.stage(adapt: { $0.prefix(1) }) == .staged)
        #expect(try store.readBattery(romId: romId) == Data([0x0A, 0x0A]))
    }

    // MARK: - Collect

    @Test func collectReturnsNilWithoutACoreFile() {
        #expect(file.collect() == nil)
    }

    @Test func collectCopiesANewSaveIntoTheStore() throws {
        try writeStore(Data([0x0A]), modifiedAt: Date())
        try writeCoreFile(Data([0x0B]), modifiedAt: Date())

        let collected = try #require(file.collect())

        #expect(collected.isNew)
        #expect(collected.data == Data([0x0B]))
        #expect(try store.readBattery(romId: romId) == Data([0x0B]))
    }

    /// Pausing again without having played must not touch the store, which
    /// would move its timestamp and look like fresh progress to the sync.
    @Test func collectLeavesAnUnchangedSaveAlone() throws {
        // Whole seconds, so the file system hands back exactly this date.
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        try writeStore(Data([0x0A]), modifiedAt: earlier)
        try writeCoreFile(Data([0x0A]), modifiedAt: Date())

        let collected = try #require(file.collect())

        #expect(!collected.isNew)
        #expect(store.batteryModifiedAt(romId: romId) == earlier)
    }
}
