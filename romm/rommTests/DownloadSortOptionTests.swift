import Testing
import Foundation
@testable import romm

// The Downloads tab groups by platform but lets the user change how ROMs are
// ordered within each group. This pins down the pure sort, independent of the
// view model and its persistence.

private func rom(_ id: Int, name: String, downloadedAt: Date, lastPlayedAt: Date? = nil) -> DownloadedROM {
    DownloadedROM(
        id: id,
        name: name,
        platformName: "Game Boy",
        platformSlug: "gb",
        downloadedAt: downloadedAt,
        totalSizeBytes: 0,
        localDirectory: "Game Boy/\(name)",
        files: [],
        urlCover: nil,
        lastPlayedAt: lastPlayedAt
    )
}

struct DownloadSortOptionTests {

    @Test func downloadDateSortsNewestFirst() {
        let roms = [
            rom(1, name: "Oldest", downloadedAt: Date(timeIntervalSince1970: 0)),
            rom(2, name: "Newest", downloadedAt: Date(timeIntervalSince1970: 200)),
            rom(3, name: "Middle", downloadedAt: Date(timeIntervalSince1970: 100))
        ]

        let sorted = DownloadSortOption.downloadDate.apply(to: roms)

        #expect(sorted.map(\.id) == [2, 3, 1])
    }

    @Test func alphabeticalSortsCaseInsensitively() {
        let roms = [
            rom(1, name: "zelda", downloadedAt: Date()),
            rom(2, name: "Alpha", downloadedAt: Date()),
            rom(3, name: "banana", downloadedAt: Date())
        ]

        let sorted = DownloadSortOption.alphabetical.apply(to: roms)

        #expect(sorted.map(\.name) == ["Alpha", "banana", "zelda"])
    }

    @Test func lastPlayedSortsMostRecentFirstAndPutsNeverPlayedLast() {
        let roms = [
            rom(1, name: "Played Long Ago", downloadedAt: Date(), lastPlayedAt: Date(timeIntervalSince1970: 100)),
            rom(2, name: "Never Played B", downloadedAt: Date()),
            rom(3, name: "Played Recently", downloadedAt: Date(), lastPlayedAt: Date(timeIntervalSince1970: 200)),
            rom(4, name: "Never Played A", downloadedAt: Date())
        ]

        let sorted = DownloadSortOption.lastPlayed.apply(to: roms)

        #expect(sorted.map(\.id) == [3, 1, 4, 2])
    }
}
