import Testing
import Foundation
@testable import romm

struct CoverURLResolverTests {

    @Test func joinsRelativePathOntoServerURL() {
        let resolver = CoverURLResolver(serverURL: "https://romm.example.com")

        #expect(
            resolver.absoluteURLString(for: "assets/romm/resources/roms/6/123/cover/small.png")
            == "https://romm.example.com/assets/romm/resources/roms/6/123/cover/small.png"
        )
    }

    @Test func avoidsDoubleSlashesBetweenServerAndPath() {
        let resolver = CoverURLResolver(serverURL: "https://romm.example.com/")

        #expect(
            resolver.absoluteURLString(for: "/assets/cover/small.png")
            == "https://romm.example.com/assets/cover/small.png"
        )
    }

    @Test func encodesSpacesInTheCacheBustingQuery() throws {
        let resolver = CoverURLResolver(serverURL: "https://romm.example.com")

        let resolved = try #require(
            resolver.absoluteURLString(for: "assets/cover/small.png?ts=2026-07-15 22:14:51")
        )

        #expect(resolved == "https://romm.example.com/assets/cover/small.png?ts=2026-07-15%2022:14:51")
        // The whole point of the encoding, Kingfisher needs a URL, not a String.
        #expect(URL(string: resolved) != nil)
    }

    @Test func encodesSpacesInThePathPart() throws {
        let resolver = CoverURLResolver(serverURL: "https://romm.example.com")

        let resolved = try #require(resolver.absoluteURLString(for: "assets/Super Mario/small.png"))

        #expect(resolved == "https://romm.example.com/assets/Super%20Mario/small.png")
        #expect(URL(string: resolved) != nil)
    }

    @Test func keepsAbsoluteURLsAbsolute() {
        let resolver = CoverURLResolver(serverURL: "https://romm.example.com")

        #expect(
            resolver.absoluteURLString(for: "https://cdn2.steamgriddb.com/grid/abc.png")
            == "https://cdn2.steamgriddb.com/grid/abc.png"
        )
    }

    @Test func encodesAnAbsoluteURLThatContainsSpaces() throws {
        let resolver = CoverURLResolver(serverURL: nil)

        let resolved = try #require(
            resolver.absoluteURLString(for: "https://cdn2.steamgriddb.com/grid/abc.png?ts=2026-07-15 22:14:51")
        )

        #expect(URL(string: resolved) != nil)
        #expect(resolved.contains("%20"))
    }

    @Test func leavesAlreadyEncodedURLsAlone() {
        let resolver = CoverURLResolver(serverURL: "https://romm.example.com")

        // Encoding a second time would turn the %20 into %2520 and break the request.
        #expect(
            resolver.absoluteURLString(for: "assets/Super%20Mario/small.png")
            == "https://romm.example.com/assets/Super%20Mario/small.png"
        )
    }

    @Test func returnsNilForMissingPaths() {
        let resolver = CoverURLResolver(serverURL: "https://romm.example.com")

        #expect(resolver.absoluteURLString(for: nil) == nil)
        #expect(resolver.absoluteURLString(for: "") == nil)
        #expect(resolver.absoluteURLString(for: "/") == nil)
    }

    @Test func returnsNilForRelativePathsWithoutAServerURL() {
        // A relative path is useless on its own, so the caller falls back to `url_cover`.
        #expect(CoverURLResolver(serverURL: nil).absoluteURLString(for: "assets/cover/small.png") == nil)
        #expect(CoverURLResolver(serverURL: "").absoluteURLString(for: "assets/cover/small.png") == nil)
        #expect(CoverURLResolver(serverURL: "  ").absoluteURLString(for: "assets/cover/small.png") == nil)
    }
}

struct RomCoverSelectionTests {

    private func makeRom(
        urlCover: String? = nil,
        coverURLSmall: String? = nil,
        coverURLLarge: String? = nil
    ) -> Rom {
        Rom(
            id: 1,
            name: "Super Mario World",
            platformId: 6,
            urlCover: urlCover,
            coverURLSmall: coverURLSmall,
            coverURLLarge: coverURLLarge
        )
    }

    @Test func listPrefersTheSmallServerCover() {
        let rom = makeRom(
            urlCover: "https://cdn2.steamgriddb.com/grid/abc.png",
            coverURLSmall: "https://romm.example.com/small.png",
            coverURLLarge: "https://romm.example.com/large.png"
        )

        #expect(rom.listCoverURL == "https://romm.example.com/small.png")
    }

    @Test func detailPrefersTheLargeServerCover() {
        let rom = makeRom(
            urlCover: "https://cdn2.steamgriddb.com/grid/abc.png",
            coverURLSmall: "https://romm.example.com/small.png",
            coverURLLarge: "https://romm.example.com/large.png"
        )

        #expect(rom.detailCoverURL == "https://romm.example.com/large.png")
    }

    @Test func fallsBackToTheRemoteCoverWhenTheServerHasNone() {
        let rom = makeRom(urlCover: "https://cdn2.steamgriddb.com/grid/abc.png")

        #expect(rom.listCoverURL == "https://cdn2.steamgriddb.com/grid/abc.png")
        #expect(rom.detailCoverURL == "https://cdn2.steamgriddb.com/grid/abc.png")
    }

    @Test func neverFallsBackToAFileURL() {
        // RomM reports values like this for some MAME sets, they can never be loaded.
        let rom = makeRom(urlCover: "file://roms/mame2003/downloaded_images/88games.png")

        #expect(rom.listCoverURL == nil)
        #expect(rom.detailCoverURL == nil)
    }

    @Test func detailFallsBackToTheSmallCoverAsALastResort() {
        let rom = makeRom(
            urlCover: "file://roms/mame2003/downloaded_images/88games.png",
            coverURLSmall: "https://romm.example.com/small.png"
        )

        #expect(rom.detailCoverURL == "https://romm.example.com/small.png")
    }

    @Test func romDetailsUsesTheSameCoverPreferences() {
        let details = RomDetails(
            id: 1,
            name: "Super Mario World",
            urlCover: "file://roms/mame2003/downloaded_images/88games.png",
            coverURLSmall: "https://romm.example.com/small.png",
            coverURLLarge: "https://romm.example.com/large.png",
            platformId: 6,
            platformDisplayName: "SNES"
        )

        #expect(details.listCoverURL == "https://romm.example.com/small.png")
        #expect(details.detailCoverURL == "https://romm.example.com/large.png")
    }
}
