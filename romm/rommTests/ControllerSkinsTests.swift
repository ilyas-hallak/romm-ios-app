import Testing
import Foundation
@testable import romm

// MARK: - Stubs

/// Stands in for DeltaCore so the tests don't need real `.deltaskin` archives.
/// File names listed in `rejected` are treated as unreadable skins.
private final class StubInspector: PControllerSkinInspector {
    var rejected: Set<String> = []

    /// Overrides per file name; any other name gets generic GBA skin info.
    var infos: [String: ControllerSkinInfo] = [:]

    func inspect(fileURL: URL) throws -> ControllerSkinInfo {
        let name = fileURL.lastPathComponent
        guard !rejected.contains(name) else { throw ControllerSkinError.notASkinFile }
        return infos[name] ?? ControllerSkinInfo(
            fileName: name,
            name: "Stub Skin",
            identifier: "com.stub.\(name)",
            gameTypeIdentifier: "com.rileytestut.delta.game.gba"
        )
    }
}

private final class StubPreference: PControllerSkinPreference {
    private var store: [String: String] = [:]

    func selectedFileName(forGameType gameTypeIdentifier: String) -> String? {
        store[gameTypeIdentifier]
    }

    func setSelectedFileName(_ fileName: String?, forGameType gameTypeIdentifier: String) {
        store[gameTypeIdentifier] = fileName
    }
}

// MARK: - Helpers

private func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ControllerSkinsTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The stub inspector never reads the bytes, so ZIP magic is enough to stand in
/// for a real archive.
private func placeDummySkin(named name: String, in directory: URL) -> URL {
    let url = directory.appendingPathComponent(name)
    try? Data([0x50, 0x4B, 0x00, 0x00]).write(to: url)
    return url
}

// MARK: - Repository Tests

struct ControllerSkinRepositoryTests {

    @Test func installedSkinsSkipsInvalidFiles() throws {
        let tmp = makeTempDirectory()
        let inspector = StubInspector()

        _ = placeDummySkin(named: "good.deltaskin", in: tmp)
        _ = placeDummySkin(named: "broken.deltaskin", in: tmp)
        inspector.rejected = ["broken.deltaskin"]

        let repo = ControllerSkinRepository(inspector: inspector, baseDirectory: tmp)
        let skins = try repo.installedSkins()

        #expect(skins.count == 1)
        #expect(skins.first?.fileName == "good.deltaskin")
    }

    /// Files dropped in via the Files app keep their own extension; anything
    /// that isn't a `.deltaskin` must not show up as a skin.
    @Test func installedSkinsIgnoresUnrelatedFiles() throws {
        let tmp = makeTempDirectory()
        _ = placeDummySkin(named: "notes.txt", in: tmp)
        _ = placeDummySkin(named: "archive.zip", in: tmp)
        _ = placeDummySkin(named: "real.deltaskin", in: tmp)

        let repo = ControllerSkinRepository(inspector: StubInspector(), baseDirectory: tmp)

        #expect(try repo.installedSkins().map(\.fileName) == ["real.deltaskin"])
    }

    @Test func storeSanitizesFileNameAndForcesExtension() throws {
        let store = makeTempDirectory()
        let downloads = makeTempDirectory()
        let repo = ControllerSkinRepository(inspector: StubInspector(), baseDirectory: store)

        let source = placeDummySkin(named: "source.deltaskin", in: downloads)

        // Path separators and a wrong extension, as they arrive from a URL.
        let stored = try repo.store(fileURL: source, preferredFileName: "/some/path/my:skin.zip")

        #expect(stored.fileName == "my-skin.deltaskin")
        #expect(FileManager.default.fileExists(atPath: store.appendingPathComponent("my-skin.deltaskin").path))
    }

    @Test func storeReplacesExistingSkinWithSameName() throws {
        let store = makeTempDirectory()
        let downloads = makeTempDirectory()
        let repo = ControllerSkinRepository(inspector: StubInspector(), baseDirectory: store)

        _ = try repo.store(
            fileURL: placeDummySkin(named: "first.deltaskin", in: downloads),
            preferredFileName: "skin.deltaskin"
        )
        _ = try repo.store(
            fileURL: placeDummySkin(named: "second.deltaskin", in: downloads),
            preferredFileName: "skin.deltaskin"
        )

        #expect(try repo.installedSkins().count == 1)
    }

    /// Regression: the store folder shows up in the Files app, so the picked
    /// file can be one that already lives there. Copying it onto itself used to
    /// delete the skin.
    @Test func storeKeepsSkinWhenSourceIsAlreadyInTheStore() throws {
        let store = makeTempDirectory()
        let repo = ControllerSkinRepository(inspector: StubInspector(), baseDirectory: store)
        let existing = placeDummySkin(named: "inplace.deltaskin", in: store)

        let stored = try repo.store(fileURL: existing, preferredFileName: "inplace.deltaskin")

        #expect(stored.fileName == "inplace.deltaskin")
        #expect(FileManager.default.fileExists(atPath: existing.path))
    }
}

// MARK: - UseCase Tests

struct ControllerSkinsUseCaseTests {

    private static let gba = "com.rileytestut.delta.game.gba"

    @Test func selectedSkinReturnsNilAndCleansPreferenceWhenFileDeleted() throws {
        let store = makeTempDirectory()
        let downloads = makeTempDirectory()
        let preference = StubPreference()
        let repo = ControllerSkinRepository(inspector: StubInspector(), baseDirectory: store)
        let useCase = ControllerSkinsUseCase(
            repository: repo,
            preference: preference,
            downloader: ControllerSkinDownloadService()  // not exercised here
        )

        let stored = try repo.store(
            fileURL: placeDummySkin(named: "ghost.deltaskin", in: downloads),
            preferredFileName: "ghost.deltaskin"
        )
        useCase.select(stored, forGameType: Self.gba)

        // The user removed the file behind the app's back, e.g. via the Files app.
        try repo.delete(stored)

        #expect(useCase.selectedSkin(forGameType: Self.gba) == nil)
        #expect(preference.selectedFileName(forGameType: Self.gba) == nil)
    }

    @Test func selectedSkinFileURLPointsAtTheStoredFile() throws {
        let store = makeTempDirectory()
        let downloads = makeTempDirectory()
        let repo = ControllerSkinRepository(inspector: StubInspector(), baseDirectory: store)
        let useCase = ControllerSkinsUseCase(
            repository: repo,
            preference: StubPreference(),
            downloader: ControllerSkinDownloadService()
        )

        let stored = try repo.store(
            fileURL: placeDummySkin(named: "chosen.deltaskin", in: downloads),
            preferredFileName: "chosen.deltaskin"
        )

        #expect(useCase.selectedSkinFileURL(forGameType: Self.gba) == nil)

        useCase.select(stored, forGameType: Self.gba)

        #expect(useCase.selectedSkinFileURL(forGameType: Self.gba)?.lastPathComponent == "chosen.deltaskin")
    }
}

// MARK: - DeltaGameType Roundtrip Tests

struct DeltaGameTypeSkinsTests {

    @Test func roundtripForEveryGameType() {
        for gameType in DeltaGameType.allCases {
            let roundtripped = DeltaGameType(gameTypeIdentifier: gameType.gameTypeIdentifier)
            #expect(roundtripped == gameType, "Roundtrip failed for \(gameType.rawValue)")
        }
    }

    @Test func unknownIdentifierReturnsNil() {
        #expect(DeltaGameType(gameTypeIdentifier: "com.rileytestut.delta.game.unknown") == nil)
        #expect(DeltaGameType(gameTypeIdentifier: "not.a.game.type") == nil)
    }
}
