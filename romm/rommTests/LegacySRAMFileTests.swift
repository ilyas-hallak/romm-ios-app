import Testing
import Foundation
@testable import romm

struct LegacySRAMFileTests {

    private let romId = 7
    private let root: URL
    private let store: LocalSaveStoreRepository
    private let saveStates: EmulatorSaveStatesUseCase
    private let legacyURL: URL
    private let url: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacySRAMFileTests-\(UUID().uuidString)", isDirectory: true)
        let saves = root.appendingPathComponent("LibretroSaves", isDirectory: true)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        store = LocalSaveStoreRepository(rootDirectory: root.appendingPathComponent("Store"))
        saveStates = EmulatorSaveStatesUseCase(saveStore: store)
        legacyURL = saves.appendingPathComponent("Game.srm")
        url = saves.appendingPathComponent("\(romId)-Game.srm")
    }

    private func migration(owners: Set<Int>) -> LegacySRAMFile {
        LegacySRAMFile(
            legacyURL: legacyURL,
            url: url,
            romId: romId,
            saveStates: saveStates,
            findROMsByFileStem: FixedStemOwners(owners: owners)
        )
    }

    private var coreFile: CoreBatteryFile {
        CoreBatteryFile(url: url, romId: romId, saveStates: saveStates)
    }

    private func writeLegacy(_ data: Data, modifiedAt date: Date) throws {
        try data.write(to: legacyURL)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: legacyURL.path)
    }

    private func writeStore(_ data: Data, modifiedAt date: Date) throws {
        try store.writeBattery(romId: romId, data: data)
        try store.setBatteryModifiedAt(romId: romId, date: date)
    }

    private func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    @Test func takesAFileThatMatchesTheStoredSaveEvenWhenTheNameIsShared() throws {
        try writeStore(Data([0x0A]), modifiedAt: Date())
        try writeLegacy(Data([0x0A]), modifiedAt: Date())

        #expect(migration(owners: [romId, 99]).migrate())
        #expect(contents(url) == Data([0x0A]))
    }

    /// Issue #189 before the update: the game was swiped away, so the old file
    /// holds progress the store never saw.
    @Test func takesNewerProgressWhenNoOtherROMHasTheName() throws {
        let now = Date()
        try writeStore(Data([0x0A]), modifiedAt: now.addingTimeInterval(-600))
        try writeLegacy(Data([0x0B]), modifiedAt: now)

        #expect(migration(owners: [romId]).migrate())
        #expect(coreFile.stage() == .adoptedCoreFile(Data([0x0B])))
        #expect(try store.readBattery(romId: romId) == Data([0x0B]))
        #expect(contents(legacyURL) == Data([0x0B]))
    }

    @Test func leavesAFileAloneWhenAnotherROMHasTheSameName() throws {
        let now = Date()
        try writeStore(Data([0x0A]), modifiedAt: now.addingTimeInterval(-600))
        try writeLegacy(Data([0x0B]), modifiedAt: now)

        #expect(!migration(owners: [romId, 99]).migrate())
        #expect(coreFile.stage() == .staged)
        #expect(try store.readBattery(romId: romId) == Data([0x0A]))
        #expect(contents(url) == Data([0x0A]))
        #expect(contents(legacyURL) == Data([0x0B]))
    }

    /// The store got newer while the old file sat there, from another device
    /// for example, so the store still wins.
    @Test func anOlderFileLosesToTheStoreButStaysOnDisk() throws {
        let now = Date()
        try writeLegacy(Data([0x0B]), modifiedAt: now.addingTimeInterval(-600))
        try writeStore(Data([0x0A]), modifiedAt: now)

        migration(owners: []).migrate()

        #expect(coreFile.stage() == .staged)
        #expect(contents(url) == Data([0x0A]))
        #expect(contents(legacyURL) == Data([0x0B]))
    }

    @Test func neverReplacesAFileUnderTheNewName() throws {
        try Data([0x0C]).write(to: url)
        try writeLegacy(Data([0x0B]), modifiedAt: Date())

        #expect(!migration(owners: []).migrate())
        #expect(contents(url) == Data([0x0C]))
    }
}

private struct FixedStemOwners: PFindROMsByFileStemUseCase {
    let owners: Set<Int>
    func execute(stem: String) throws -> Set<Int> { owners }
}
