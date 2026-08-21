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

/// Stub downloader that returns a pre-configured result without making network calls.
private final class StubDownloader: PControllerSkinDownloader {
    var result: ControllerSkinDownload

    init(result: ControllerSkinDownload) {
        self.result = result
    }

    func download(from url: URL) async throws -> ControllerSkinDownload {
        result
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

private func makeUseCase(
    store: URL,
    downloader: PControllerSkinDownloader,
    parser: PControllerSkinLinkParser = HTMLControllerSkinLinkParser()
) -> ControllerSkinsUseCase {
    ControllerSkinsUseCase(
        repository: ControllerSkinRepository(inspector: StubInspector(), baseDirectory: store),
        preference: StubPreference(),
        downloader: downloader,
        linkParser: parser
    )
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
        // Downloader is not exercised in this test; a skin-returning stub keeps it clean.
        let stubTempURL = placeDummySkin(named: "ghost.deltaskin", in: downloads)
        let useCase = ControllerSkinsUseCase(
            repository: repo,
            preference: preference,
            downloader: StubDownloader(result: .skin(fileURL: stubTempURL)),
            linkParser: HTMLControllerSkinLinkParser()
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
        let stubTempURL = placeDummySkin(named: "chosen.deltaskin", in: downloads)
        let useCase = ControllerSkinsUseCase(
            repository: repo,
            preference: StubPreference(),
            downloader: StubDownloader(result: .skin(fileURL: stubTempURL)),
            linkParser: HTMLControllerSkinLinkParser()
        )

        let stored = try repo.store(
            fileURL: placeDummySkin(named: "chosen.deltaskin", in: downloads),
            preferredFileName: "chosen.deltaskin"
        )

        #expect(useCase.selectedSkinFileURL(forGameType: Self.gba) == nil)

        useCase.select(stored, forGameType: Self.gba)

        #expect(useCase.selectedSkinFileURL(forGameType: Self.gba)?.lastPathComponent == "chosen.deltaskin")
    }

    // MARK: importSkin

    @Test func importSkinWithSkinDownloadReturnsImported() async throws {
        let store = makeTempDirectory()
        let downloads = makeTempDirectory()
        let tempSkin = placeDummySkin(named: "cool.deltaskin", in: downloads)
        let useCase = makeUseCase(store: store, downloader: StubDownloader(result: .skin(fileURL: tempSkin)))

        let result = try await useCase.importSkin(from: URL(string: "https://example.com/cool.deltaskin")!)

        guard case .imported(let info) = result else {
            Issue.record("Expected .imported, got \(result)")
            return
        }
        #expect(info.fileName == "cool.deltaskin")
    }

    @Test func importSkinWithWebPageAndLinksReturnsChoices() async throws {
        let store = makeTempDirectory()
        let html = """
        <img data-download='https://example.com/purple.deltaskin' alt="Purple Skin">
        """
        let useCase = makeUseCase(store: store, downloader: StubDownloader(result: .webPage(html: html)))

        let result = try await useCase.importSkin(from: URL(string: "https://example.com/skins.html")!)

        guard case .choices(let links) = result else {
            Issue.record("Expected .choices, got \(result)")
            return
        }
        #expect(links.count == 1)
        #expect(links.first?.name == "Purple Skin")
    }

    @Test func importSkinWithEmptyPageThrowsNoSkinsOnPage() async throws {
        let store = makeTempDirectory()
        let useCase = makeUseCase(store: store, downloader: StubDownloader(result: .webPage(html: "<html><body>No skins here.</body></html>")))

        await #expect(throws: ControllerSkinError.noSkinsOnPage) {
            _ = try await useCase.importSkin(from: URL(string: "https://example.com/empty.html")!)
        }
    }

    @Test func addSkinFromLinkWithWebPageThrowsNotASkinFile() async throws {
        let store = makeTempDirectory()
        let useCase = makeUseCase(store: store, downloader: StubDownloader(result: .webPage(html: "<html></html>")))
        let link = ControllerSkinLink(name: "Page", url: URL(string: "https://example.com/page.html")!)

        await #expect(throws: ControllerSkinError.notASkinFile) {
            _ = try await useCase.addSkin(from: link)
        }
    }
}

// MARK: - HTMLControllerSkinLinkParser Tests

struct HTMLControllerSkinLinkParserTests {

    private let parser = HTMLControllerSkinLinkParser()
    private let pageURL = URL(string: "https://delta-skins.github.io/snes.html")!

    // Real-world fixture from delta-skins.github.io (three entries).
    private let fixture = """
    <img data-console="snes" src="snes/purple snes.png" data-maker="Pixel Miku" data-supports="All phones" onclick="onClick(this)" data-download='https://github.com/delta-skins/delta-skins.github.io/raw/master/snes/Purple_SNES.deltaskin' alt="Purple SNES">
    <img data-console="snes" src="snes/classic.png" data-maker="Retro" data-supports="All phones" onclick="onClick(this)" data-download='https://github.com/delta-skins/delta-skins.github.io/raw/master/snes/Classic_SNES.deltaskin' alt="Classic SNES">
    <img data-console="snes" src="snes/minimal.png" data-maker="Min" data-supports="All phones" onclick="onClick(this)" data-download='https://github.com/delta-skins/delta-skins.github.io/raw/master/snes/Minimal_SNES.deltaskin' alt="Minimal SNES">
    """

    @Test func realWorldFixtureExtractsCorrectURLsAndNames() {
        let links = parser.links(in: fixture, pageURL: pageURL)

        #expect(links.count == 3)
        #expect(links[0].name == "Purple SNES")
        #expect(links[0].url.absoluteString == "https://github.com/delta-skins/delta-skins.github.io/raw/master/snes/Purple_SNES.deltaskin")
        #expect(links[1].name == "Classic SNES")
        #expect(links[2].name == "Minimal SNES")
    }

    @Test func relativePathsAreResolvedAgainstPageURL() {
        let html = #"<a href="skins/My_Skin.deltaskin">Download</a>"#
        let base = URL(string: "https://example.com/catalog/index.html")!

        let links = parser.links(in: html, pageURL: base)

        #expect(links.count == 1)
        #expect(links.first?.url.absoluteString == "https://example.com/catalog/skins/My_Skin.deltaskin")
    }

    @Test func hrefAttributeWorksLikeDataDownload() {
        let html = #"<a href="https://example.com/GBA_Dark.deltaskin" title="GBA Dark">GBA Dark</a>"#

        let links = parser.links(in: html, pageURL: pageURL)

        #expect(links.count == 1)
        #expect(links.first?.url.absoluteString == "https://example.com/GBA_Dark.deltaskin")
        // title attribute used as display name
        #expect(links.first?.name == "GBA Dark")
    }

    @Test func duplicateURLsAreRemovedOrderPreserved() {
        let html = """
        <a href='https://example.com/skin.deltaskin'>First mention</a>
        <a href='https://example.com/other.deltaskin'>Other</a>
        <a href='https://example.com/skin.deltaskin'>Duplicate</a>
        """

        let links = parser.links(in: html, pageURL: pageURL)

        #expect(links.count == 2)
        #expect(links[0].url.lastPathComponent == "skin.deltaskin")
        #expect(links[1].url.lastPathComponent == "other.deltaskin")
    }

    @Test func pageWithoutDeltaskinLinksReturnsEmptyArray() {
        let html = "<html><body><a href='https://example.com/readme.txt'>Read me</a></body></html>"

        #expect(parser.links(in: html, pageURL: pageURL).isEmpty)
    }

    @Test func fileNameFallbackConvertsUnderscoresAndPercentEncoding() {
        // No alt or title on this tag, so the name should be derived from the URL.
        let html = #"<a href="https://example.com/Purple_SNES.deltaskin">Get it</a>"#

        let links = parser.links(in: html, pageURL: pageURL)

        #expect(links.first?.name == "Purple SNES")
    }

    @Test func nonHTTPSchemesAreIgnored() {
        // ftp:// link should be discarded.
        let html = #"<a href="ftp://example.com/skin.deltaskin">FTP skin</a>"#

        #expect(parser.links(in: html, pageURL: pageURL).isEmpty)
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
