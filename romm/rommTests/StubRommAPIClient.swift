import Foundation
@testable import romm

/// A `PRommAPIClient` whose every call fails until a subclass overrides it.
///
/// The protocol has fifty-odd requirements while a given test needs one or two,
/// so without this each test file carries forty-nine stubs of its own before it
/// can say anything. Failing loudly rather than returning an empty value is
/// deliberate: a test that reaches an unstubbed call is testing a path it did
/// not mean to, and a plausible-looking default would hide that.
class StubRommAPIClient: PRommAPIClient {
    func makeRequest<T: Codable>(path: String, method: HTTPMethod, body: Data?, responseType: T.Type) async throws -> T { fatalError("makeRequest not stubbed") }
    func makeRequest(path: String, method: HTTPMethod, body: Data?) async throws -> Data { fatalError("makeRequest not stubbed") }
    func downloadFile(path: String, progressHandler: ((Int64, Int64) -> Void)?) async throws -> URL { fatalError("downloadFile not stubbed") }
    func multipartRequest(path: String, method: HTTPMethod, boundary: String, formData: Data, additionalHeaders: [String: String]?) async throws -> Data { fatalError("multipartRequest not stubbed") }
    func get<T: Codable>(_ path: String, responseType: T.Type) async throws -> T { fatalError("get not stubbed") }
    func get(_ path: String) async throws -> Data { fatalError("get not stubbed") }
    func getBinary(_ path: String) async throws -> Data { fatalError("getBinary not stubbed") }
    func post<RequestBody: Codable, ResponseType: Codable>(_ path: String, body: RequestBody, responseType: ResponseType.Type) async throws -> ResponseType { fatalError("post not stubbed") }
    func post(_ path: String, body: Data?) async throws -> Data { fatalError("post not stubbed") }
    func put<RequestBody: Codable, ResponseType: Codable>(_ path: String, body: RequestBody, responseType: ResponseType.Type) async throws -> ResponseType { fatalError("put not stubbed") }
    func put<RequestBody: Codable>(_ path: String, body: RequestBody) async throws -> Data { fatalError("put not stubbed") }
    func put(_ path: String, body: Data?) async throws -> Data { fatalError("put not stubbed") }
    func delete(_ path: String) async throws -> Data { fatalError("delete not stubbed") }
    func getRomManual(romId: Int) async throws -> Manual? { fatalError("getRomManual not stubbed") }
    func getManualPDFData(manualURL: String) async throws -> Data { fatalError("getManualPDFData not stubbed") }
    func getRomDetails(id: Int) async throws -> DetailedRomSchema { fatalError("getRomDetails not stubbed") }
    func getRoms( searchTerm: String?, platformId: Int?, limit: Int ) async throws -> CustomLimitOffsetPageSimpleRomSchema { fatalError("getRoms not stubbed") }
    func getRomsWithFilters( searchTerm: String?, platformId: Int?, collectionId: Int?, limit: Int, offset: Int?, withCharIndex: Bool?, orderBy: String?, orderDir: String?, filters: RomFilters ) async throws -> CustomLimitOffsetPageSimpleRomSchema { fatalError("getRomsWithFilters not stubbed") }
    func searchRomsWithOpenAPI(query: String) async throws -> CustomLimitOffsetPageSimpleRomSchema { fatalError("searchRomsWithOpenAPI not stubbed") }
    func getCollections(limit: Int?, offset: Int?) async throws -> [CollectionSchema] { fatalError("getCollections not stubbed") }
    func getCollection(id: Int) async throws -> CollectionSchema { fatalError("getCollection not stubbed") }
    func getVirtualCollections(type: String, limit: Int?) async throws -> [VirtualCollectionSchema] { fatalError("getVirtualCollections not stubbed") }
    func getVirtualCollection(id: String) async throws -> VirtualCollectionSchema { fatalError("getVirtualCollection not stubbed") }
    func createCollection(name: String, description: String, isPublic: Bool, isFavorite: Bool, artwork: URL?) async throws -> CollectionSchema { fatalError("createCollection not stubbed") }
    func updateCollection(id: Int, name: String, description: String, isPublic: Bool, romIds: [Int]?, artwork: URL?) async throws -> CollectionSchema { fatalError("updateCollection not stubbed") }
    func deleteCollection(id: Int) async throws -> String { fatalError("deleteCollection not stubbed") }
    func addRomsToCollection(id: Int, romIds: [Int]) async throws -> CollectionSchema { fatalError("addRomsToCollection not stubbed") }
    func removeRomsFromCollection(id: Int, romIds: [Int]) async throws -> CollectionSchema { fatalError("removeRomsFromCollection not stubbed") }
    func getCurrentUser() async throws -> UserSchema { fatalError("getCurrentUser not stubbed") }
    func updateRetroAchievementsUsername(userId: Int, username: String) async throws -> UserSchema { fatalError("updateRetroAchievementsUsername not stubbed") }
    func getPlatforms() async throws -> [PlatformSchema] { fatalError("getPlatforms not stubbed") }
    func addPlatform(name: String, slug: String) async throws -> PlatformSchema { fatalError("addPlatform not stubbed") }
    func deletePlatform(id: Int) async throws -> String { fatalError("deletePlatform not stubbed") }
    func getPlatformFirmware(platformId: Int) async throws -> [FirmwareSchema] { fatalError("getPlatformFirmware not stubbed") }
    func downloadFirmwareContent(id: Int, fileName: String) async throws -> Data { fatalError("downloadFirmwareContent not stubbed") }
    func getHeartbeat() async throws -> HeartbeatResponse { fatalError("getHeartbeat not stubbed") }
    func getHeartbeat(from serverURL: String) async throws -> HeartbeatResponse { fatalError("getHeartbeat not stubbed") }
    func updateRomLastPlayed(id: Int) async throws -> RomUserSchema { fatalError("updateRomLastPlayed not stubbed") }
    func getStats() async throws -> StatsReturn { fatalError("getStats not stubbed") }
    func getSaves(romId: Int) async throws -> [SaveSchema] { fatalError("getSaves not stubbed") }
    func getStates(romId: Int) async throws -> [StateSchema] { fatalError("getStates not stubbed") }
    func uploadSave(romId: Int, emulator: String?, slot: String?, deviceId: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema { fatalError("uploadSave not stubbed") }
    func updateSave(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema { fatalError("updateSave not stubbed") }
    func downloadSave(id: Int, deviceId: String?) async throws -> Data { fatalError("downloadSave not stubbed") }
    func deleteSaves(ids: [Int]) async throws { fatalError("deleteSaves not stubbed") }
    func uploadState(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema { fatalError("uploadState not stubbed") }
    func updateState(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema { fatalError("updateState not stubbed") }
    func downloadState(id: Int) async throws -> Data { fatalError("downloadState not stubbed") }
    func deleteStates(ids: [Int]) async throws { fatalError("deleteStates not stubbed") }
    func registerDevice(_ body: DeviceRegisterRequest) async throws -> DeviceSchema { fatalError("registerDevice not stubbed") }
    func negotiateSync(_ body: SyncNegotiateRequest) async throws -> SyncNegotiateResponse { fatalError("negotiateSync not stubbed") }
}
