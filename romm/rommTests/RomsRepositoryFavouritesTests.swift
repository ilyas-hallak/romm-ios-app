import Testing
import Foundation
@testable import romm

// FakeAPIClient, the makeCollection/makeUser fixtures, and FakeAPIError live in
// Support/FakeAPIClient.swift so several test files can share them.

struct RomsRepositoryFavouritesTests {

    @Test func addsRomToExistingFavouritesCollection() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.collectionsToReturn = [
            makeCollection(id: 3, userId: 7, isFavorite: false, name: "Shooters"),
            makeCollection(id: 42, userId: 7, isFavorite: true)
        ]
        let repository = RomsRepository(apiClient: api)

        try await repository.toggleRomFavorite(romId: 100, isFavorite: true)

        #expect(api.createCollectionCallCount == 0)
        #expect(api.addedRoms.count == 1)
        #expect(api.addedRoms.first?.collectionId == 42)
        #expect(api.addedRoms.first?.romIds == [100])
    }

    @Test func createsFavouritesCollectionWhenMissingBeforeAdding() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.createdCollectionId = 55
        api.collectionsToReturn = []
        let repository = RomsRepository(apiClient: api)

        try await repository.toggleRomFavorite(romId: 100, isFavorite: true)

        #expect(api.createCollectionCallCount == 1)
        #expect(api.createdCollectionNames == ["Favorites"])
        #expect(api.createdCollectionIsPublic == [false])
        #expect(api.createdCollectionIsFavorite == [true])
        #expect(api.addedRoms.count == 1)
        #expect(api.addedRoms.first?.collectionId == 55)
        #expect(api.addedRoms.first?.romIds == [100])
    }

    @Test func ignoresForeignFavouritesCollectionAndCreatesOwnOne() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.createdCollectionId = 55
        // Public favourites collection of another user, as returned by the collections endpoint.
        api.collectionsToReturn = [makeCollection(id: 2, userId: 9, isFavorite: true)]
        let repository = RomsRepository(apiClient: api)

        try await repository.toggleRomFavorite(romId: 100, isFavorite: true)

        #expect(api.createCollectionCallCount == 1)
        #expect(api.addedRoms.count == 1)
        #expect(api.addedRoms.first?.collectionId == 55)
        #expect(api.addedRoms.contains { $0.collectionId == 2 } == false)
    }

    @Test func removesRomFromExistingFavouritesCollection() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.collectionsToReturn = [makeCollection(id: 42, userId: 7, isFavorite: true, romIds: [100])]
        let repository = RomsRepository(apiClient: api)

        try await repository.toggleRomFavorite(romId: 100, isFavorite: false)

        #expect(api.removedRoms.count == 1)
        #expect(api.removedRoms.first?.collectionId == 42)
        #expect(api.removedRoms.first?.romIds == [100])
        #expect(api.createCollectionCallCount == 0)
    }

    @Test func removeIsNoOpWithoutFavouritesCollection() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.collectionsToReturn = []
        let repository = RomsRepository(apiClient: api)

        try await repository.toggleRomFavorite(romId: 100, isFavorite: false)

        #expect(api.createCollectionCallCount == 0)
        #expect(api.removedRoms.isEmpty)
        #expect(api.addedRoms.isEmpty)
    }

    @Test func isRomFavoriteReturnsTrueWhenCollectionContainsRom() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.collectionsToReturn = [makeCollection(id: 42, userId: 7, isFavorite: true, romIds: [100, 101])]
        let repository = RomsRepository(apiClient: api)

        #expect(try await repository.isRomFavorite(romId: 100) == true)
    }

    @Test func isRomFavoriteReturnsFalseWhenCollectionDoesNotContainRom() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.collectionsToReturn = [makeCollection(id: 42, userId: 7, isFavorite: true, romIds: [101])]
        let repository = RomsRepository(apiClient: api)

        #expect(try await repository.isRomFavorite(romId: 100) == false)
    }

    @Test func isRomFavoriteReturnsFalseWithoutFavouritesCollection() async throws {
        let api = FakeAPIClient()
        api.currentUserId = 7
        api.collectionsToReturn = [makeCollection(id: 2, userId: 9, isFavorite: true, romIds: [100])]
        let repository = RomsRepository(apiClient: api)

        #expect(try await repository.isRomFavorite(romId: 100) == false)
    }

    @Test func toggleThrowsNetworkErrorWhenCollectionLookupFails() async {
        let api = FakeAPIClient()
        api.errorToThrow = FakeAPIError()
        let repository = RomsRepository(apiClient: api)

        do {
            try await repository.toggleRomFavorite(romId: 100, isFavorite: true)
            Issue.record("expected RomError.networkError")
        } catch {
            #expect(error as? RomError == .networkError)
        }
    }
}
