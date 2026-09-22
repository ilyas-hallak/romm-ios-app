//
//  RomDetailViewModelFavouriteTests.swift
//  rommTests
//
//  Covers the sibling-switch bug: a failed favourite check must not leak the
//  previous ROM's favourite status onto a different ROM.
//

import Testing
import Foundation
@testable import romm

// `RomDetailViewModel.init` eagerly builds `getDownloadedROM`, which needs a
// `localROMRepository`. `MockDependencyFactory` traps if that is left
// unstubbed, so every test here must inject something even though loading
// ROM details never reads from it.
private final class FakeLocalROMs: PLocalROMRepository, @unchecked Sendable {
    var romsBaseURL: URL { FileManager.default.temporaryDirectory }

    func getAllDownloadedROMs() throws -> [DownloadedROM] { [] }
    func getDownloadedROMsByPlatform() throws -> [String: [DownloadedROM]] { [:] }
    func getDownloadedROM(byId id: Int) throws -> DownloadedROM? { nil }
    func saveDownloadedROM(_ rom: DownloadedROM) throws {}
    func deleteDownloadedROM(_ rom: DownloadedROM) throws {}
    func getTotalDownloadedSize() throws -> Int64 { 0 }
    func getDownloadedROMsCount() throws -> Int { 0 }
}

@MainActor
struct RomDetailViewModelFavouriteTests {

    @Test func keepsLastKnownStatusWhenSameRomCheckFails() async throws {
        let romsRepository = FakeRomsRepositoryForFavouriteTests()
        romsRepository.detailsById[1] = makeRomDetails(id: 1)
        romsRepository.favoriteStatusById[1] = true

        let factory = MockDependencyFactory(romsRepository: romsRepository, localROMRepository: FakeLocalROMs())
        let viewModel = RomDetailViewModel(factory: factory)

        await viewModel.loadRomDetails(romId: 1)
        #expect(viewModel.actualFavoriteStatus == true)

        // Second load of the SAME rom, but this time the favourite check fails.
        romsRepository.failFavoriteCheckForIds.insert(1)
        await viewModel.loadRomDetails(romId: 1)

        #expect(viewModel.actualFavoriteStatus == true)
    }

    @Test func defaultsToFalseWhenADifferentRomCheckFails() async throws {
        let romsRepository = FakeRomsRepositoryForFavouriteTests()
        romsRepository.detailsById[1] = makeRomDetails(id: 1)
        romsRepository.detailsById[2] = makeRomDetails(id: 2)
        romsRepository.favoriteStatusById[1] = true

        let factory = MockDependencyFactory(romsRepository: romsRepository, localROMRepository: FakeLocalROMs())
        let viewModel = RomDetailViewModel(factory: factory)

        await viewModel.loadRomDetails(romId: 1)
        #expect(viewModel.actualFavoriteStatus == true)

        // A sibling switch to a DIFFERENT rom whose favourite check fails.
        romsRepository.failFavoriteCheckForIds.insert(2)
        await viewModel.loadRomDetails(romId: 2)

        #expect(viewModel.actualFavoriteStatus == false)
    }
}

private func makeRomDetails(id: Int) -> RomDetails {
    RomDetails(
        id: id,
        name: "Rom \(id)",
        platformId: 1,
        platformDisplayName: "Test Platform"
    )
}

/// Minimal `PRomsRepository` double for exercising `RomDetailViewModel.loadRomDetails`.
/// Serves canned `RomDetails` per ROM id and lets a test fail the favourite lookup for
/// specific ids, independent of the ROM details and collections calls.
final class FakeRomsRepositoryForFavouriteTests: PRomsRepository {
    var detailsById: [Int: RomDetails] = [:]
    var favoriteStatusById: [Int: Bool] = [:]
    var failFavoriteCheckForIds: Set<Int> = []

    func getRomDetails(id: Int) async throws -> RomDetails {
        guard let details = detailsById[id] else {
            fatalError("FakeRomsRepositoryForFavouriteTests: no fixture for rom \(id)")
        }
        return details
    }

    func isRomFavorite(romId: Int) async throws -> Bool {
        if failFavoriteCheckForIds.contains(romId) {
            throw FakeAPIError()
        }
        return favoriteStatusById[romId] ?? false
    }

    func toggleRomFavorite(romId: Int, isFavorite: Bool) async throws {
        favoriteStatusById[romId] = isFavorite
    }

    func updateLastPlayed(romId: Int) async throws {}

    func searchRoms(query: String) async throws -> [Rom] { [] }

    func searchRomsLegacy(query: String) async throws -> [Rom] { [] }

    func getRoms(platformId: Int?, searchTerm: String?, limit: Int, offset: Int, char: String?, orderBy: String?, orderDir: String?, collectionId: Int?) async throws -> PaginatedRomsResponse {
        fatalError("not used in these tests")
    }

    func getRomsWithFilters(platformId: Int?, searchTerm: String?, limit: Int, offset: Int, char: String?, orderBy: String?, orderDir: String?, collectionId: Int?, filters: RomFilters) async throws -> PaginatedRomsResponse {
        fatalError("not used in these tests")
    }
}
