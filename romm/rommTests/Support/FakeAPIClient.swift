//
//  FakeAPIClient.swift
//  rommTests
//
//  Shared test double for PRommAPIClient, used across several test files.
//

import Foundation
@testable import romm

/// Serves canned collections and records the favourite-related writes, so the
/// repository's lookup/create logic can be exercised without a server.
final class FakeAPIClient: PRommAPIClient {
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

    /// Response served by both `getHeartbeat` overloads. `HeartbeatResponse` has
    /// too many non-optional dictionaries to build a sensible default, so tests
    /// that need a heartbeat set this explicitly; unset means the call throws.
    var heartbeatToReturn: HeartbeatResponse?

    /// Platforms served by `getPlatforms`; empty by default so a test can also
    /// exercise the empty-list path without extra setup.
    var platformsToReturn: [PlatformSchema] = []

    var addPlatformCallCount = 0
    var addedPlatforms: [(name: String, slug: String)] = []
    /// Id handed back by `addPlatform`, so tests can assert the new platform lands in the list.
    var addedPlatformId = 77

    // MARK: - Favourites relevant

    func getCurrentUser() async throws -> UserSchema {
        if let errorToThrow { throw errorToThrow }
        return makeUser(id: currentUserId)
    }

    func updateRetroAchievementsUsername(userId: Int, username: String) async throws -> UserSchema { fatalError("not used in these tests") }

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

    // MARK: - Heartbeat

    func getHeartbeat() async throws -> HeartbeatResponse {
        if let errorToThrow { throw errorToThrow }
        guard let heartbeatToReturn else { fatalError("not stubbed: getHeartbeat") }
        return heartbeatToReturn
    }

    func getHeartbeat(from serverURL: String) async throws -> HeartbeatResponse {
        if let errorToThrow { throw errorToThrow }
        guard let heartbeatToReturn else { fatalError("not stubbed: getHeartbeat(from:)") }
        return heartbeatToReturn
    }

    // MARK: - Unused

    func makeRequest<T: Codable>(path: String, method: HTTPMethod, body: Data?, responseType: T.Type) async throws -> T { fatalError("not used in these tests") }
    func makeRequest(path: String, method: HTTPMethod, body: Data?) async throws -> Data { fatalError("not used in these tests") }
    func downloadFile(path: String, expectedSize: Int64, progressHandler: ((Int64, Int64, Double?) -> Void)?) async throws -> URL { fatalError("not used in these tests") }
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
    func getPlatforms() async throws -> [PlatformSchema] {
        if let errorToThrow { throw errorToThrow }
        return platformsToReturn
    }
    func addPlatform(name: String, slug: String) async throws -> PlatformSchema {
        if let errorToThrow { throw errorToThrow }
        addPlatformCallCount += 1
        addedPlatforms.append((name: name, slug: slug))
        return makePlatform(id: addedPlatformId, name: name, slug: slug)
    }
    func deletePlatform(id: Int) async throws -> String { fatalError("not used in these tests") }
    func getPlatformFirmware(platformId: Int) async throws -> [FirmwareSchema] { fatalError("not used in these tests") }
    func downloadFirmwareContent(id: Int, fileName: String) async throws -> Data { fatalError("not used in these tests") }
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

func makeCollection(
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

func makePlatform(
    id: Int,
    name: String,
    slug: String,
    romCount: Int = 0,
    fsSizeBytes: Int = 0
) -> PlatformSchema {
    PlatformSchema(
        id: id,
        slug: slug,
        fsSlug: slug,
        romCount: romCount,
        name: name,
        igdbSlug: nil,
        mobySlug: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0),
        fsSizeBytes: fsSizeBytes,
        isUnidentified: false,
        isIdentified: true,
        missingFromFs: false,
        displayName: name
    )
}

func makeUser(id: Int) -> UserSchema {
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

struct FakeAPIError: Error {}
