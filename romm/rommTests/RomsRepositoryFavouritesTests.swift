import Testing
import Foundation
@testable import romm

/// Serves canned collections and records the favourite-related writes, so the
/// repository's lookup/create logic can be exercised without a server.
private final class FakeAPIClient: PRommAPIClient {
    var collectionsToReturn: [CollectionSchema] = []
    var currentUserId: Int = 1
    var errorToThrow: Error?

    var createCollectionCallCount = 0
    var createdCollectionNames: [String] = []
    var createdCollectionIsPublic: [Bool] = []
    var createdCollectionIsFavorite: [Bool] = []
    /// Id handed back by `createCollection`, so tests can assert the ROM lands in the new collection.
    var createdCollectionId = 99

    var addedRoms: [(collectionId: Int, romIds: [Int])] = []
    var removedRoms: [(collectionId: Int, romIds: [Int])] = []

    // MARK: - Favourites relevant

    func getCurrentUser() async throws -> UserSchema {
        if let errorToThrow { throw errorToThrow }
        return makeUser(id: currentUserId)
    }

    func getCollections(limit: Int?, offset: Int?) async throws -> [CollectionSchema] {
        if let errorToThrow { throw errorToThrow }
        return collectionsToReturn
    }

    func createCollection(name: String, description: String, isPublic: Bool, isFavorite: Bool, artwork: URL?) async throws -> CollectionSchema {
        if let errorToThrow { throw errorToThrow }
        createCollectionCallCount += 1
        createdCollectionNames.append(name)
        createdCollectionIsPublic.append(isPublic)
        createdCollectionIsFavorite.append(isFavorite)
        return makeCollection(id: createdCollectionId, userId: currentUserId, isFavorite: isFavorite, name: name)
    }

    func addRomsToCollection(id: Int, romIds: [Int]) async throws -> CollectionSchema {
        if let errorToThrow { throw errorToThrow }
        addedRoms.append((collectionId: id, romIds: romIds))
        return makeCollection(id: id, userId: currentUserId, isFavorite: true, romIds: Set(romIds))
    }

    func removeRomsFromCollection(id: Int, romIds: [Int]) async throws -> CollectionSchema {
        if let errorToThrow { throw errorToThrow }
        removedRoms.append((collectionId: id, romIds: romIds))
        return makeCollection(id: id, userId: currentUserId, isFavorite: true)
    }

    // MARK: - Unused

    func makeRequest<T: Codable>(path: String, method: HTTPMethod, body: Data?, responseType: T.Type) async throws -> T { fatalError("not used in these tests") }
    func makeRequest(path: String, method: HTTPMethod, body: Data?) async throws -> Data { fatalError("not used in these tests") }
    func downloadFile(path: String, progressHandler: ((Int64, Int64) -> Void)?) async throws -> URL { fatalError("not used in these tests") }
    func multipartRequest(path: String, method: HTTPMethod, boundary: String, formData: Data, additionalHeaders: [String: String]?) async throws -> Data { fatalError("not used in these tests") }
    func get<T: Codable>(_ path: String, responseType: T.Type) async throws -> T { fatalError("not used in these tests") }
    func get(_ path: String) async throws -> Data { fatalError("not used in these tests") }
    func getBinary(_ path: String) async throws -> Data { fatalError("not used in these tests") }
    func post<RequestBody: Codable, ResponseType: Codable>(_ path: String, body: RequestBody, responseType: ResponseType.Type) async throws -> ResponseType { fatalError("not used in these tests") }
    func post(_ path: String, body: Data?) async throws -> Data { fatalError("not used in these tests") }
    func put<RequestBody: Codable, ResponseType: Codable>(_ path: String, body: RequestBody, responseType: ResponseType.Type) async throws -> ResponseType { fatalError("not used in these tests") }
    func put<RequestBody: Codable>(_ path: String, body: RequestBody) async throws -> Data { fatalError("not used in these tests") }
    func put(_ path: String, body: Data?) async throws -> Data { fatalError("not used in these tests") }
    func delete(_ path: String) async throws -> Data { fatalError("not used in these tests") }
    func getRomManual(romId: Int) async throws -> Manual? { fatalError("not used in these tests") }
    func getManualPDFData(manualURL: String) async throws -> Data { fatalError("not used in these tests") }
    func getRomDetails(id: Int) async throws -> DetailedRomSchema { fatalError("not used in these tests") }
    func getRoms(searchTerm: String?, platformId: Int?, limit: Int) async throws -> CustomLimitOffsetPageSimpleRomSchema { fatalError("not used in these tests") }
    func getRomsWithFilters(searchTerm: String?, platformId: Int?, collectionId: Int?, limit: Int, offset: Int?, withCharIndex: Bool?, orderBy: String?, orderDir: String?, filters: RomFilters) async throws -> CustomLimitOffsetPageSimpleRomSchema { fatalError("not used in these tests") }
    func searchRomsWithOpenAPI(query: String) async throws -> CustomLimitOffsetPageSimpleRomSchema { fatalError("not used in these tests") }
    func getCollection(id: Int) async throws -> CollectionSchema { fatalError("not used in these tests") }
    func getVirtualCollections(type: String, limit: Int?) async throws -> [VirtualCollectionSchema] { fatalError("not used in these tests") }
    func getVirtualCollection(id: String) async throws -> VirtualCollectionSchema { fatalError("not used in these tests") }
    func updateCollection(id: Int, name: String, description: String, isPublic: Bool, romIds: [Int]?, artwork: URL?) async throws -> CollectionSchema { fatalError("not used in these tests") }
    func deleteCollection(id: Int) async throws -> String { fatalError("not used in these tests") }
    func getPlatforms() async throws -> [PlatformSchema] { fatalError("not used in these tests") }
    func addPlatform(name: String, slug: String) async throws -> PlatformSchema { fatalError("not used in these tests") }
    func deletePlatform(id: Int) async throws -> String { fatalError("not used in these tests") }
    func getPlatformFirmware(platformId: Int) async throws -> [FirmwareSchema] { fatalError("not used in these tests") }
    func downloadFirmwareContent(id: Int, fileName: String) async throws -> Data { fatalError("not used in these tests") }
    func getHeartbeat() async throws -> HeartbeatResponse { fatalError("not used in these tests") }
    func getHeartbeat(from serverURL: String) async throws -> HeartbeatResponse { fatalError("not used in these tests") }
    func updateRomLastPlayed(id: Int) async throws -> RomUserSchema { fatalError("not used in these tests") }
    func getStats() async throws -> StatsReturn { fatalError("not used in these tests") }
    func getSaves(romId: Int) async throws -> [SaveSchema] { fatalError("not used in these tests") }
    func getStates(romId: Int) async throws -> [StateSchema] { fatalError("not used in these tests") }
    func uploadSave(romId: Int, emulator: String?, slot: String?, deviceId: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema { fatalError("not used in these tests") }
    func updateSave(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema { fatalError("not used in these tests") }
    func downloadSave(id: Int, deviceId: String?) async throws -> Data { fatalError("not used in these tests") }
    func deleteSaves(ids: [Int]) async throws {}
    func uploadState(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema { fatalError("not used in these tests") }
    func updateState(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema { fatalError("not used in these tests") }
    func downloadState(id: Int) async throws -> Data { fatalError("not used in these tests") }
    func deleteStates(ids: [Int]) async throws {}
    func registerDevice(_ body: DeviceRegisterRequest) async throws -> DeviceSchema { fatalError("not used in these tests") }
    func negotiateSync(_ body: SyncNegotiateRequest) async throws -> SyncNegotiateResponse { fatalError("not used in these tests") }
}

// MARK: - Fixtures

private func makeCollection(
    id: Int,
    userId: Int,
    isFavorite: Bool,
    romIds: Set<Int> = [],
    name: String = "Favorites"
) -> CollectionSchema {
    CollectionSchema(
        name: name,
        description: "",
        romIds: romIds,
        romCount: romIds.count,
        pathCoverSmall: nil,
        pathCoverLarge: nil,
        pathCoversSmall: [],
        pathCoversLarge: [],
        isPublic: false,
        isFavorite: isFavorite,
        isVirtual: false,
        isSmart: false,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        id: id,
        urlCover: nil,
        userId: userId,
        userUsername: "user\(userId)"
    )
}

private func makeUser(id: Int) -> UserSchema {
    UserSchema(
        id: id,
        username: "user\(id)",
        email: nil,
        enabled: true,
        role: .viewer,
        oauthScopes: [],
        avatarPath: "",
        lastLogin: nil,
        lastActive: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}

private struct FakeAPIError: Error {}

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
