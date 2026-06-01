import Foundation

final class StatesRepository: PStatesRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient

    init(apiClient: PRommAPIClient = RommAPIClient.shared) {
        self.apiClient = apiClient
    }

    func listServerStates(romId: Int) async throws -> [StateSchema] {
        try await apiClient.getStates(romId: romId)
    }

    func uploadState(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        logger.info("☁️ Uploading state romId=\(romId) emulator=\(emulator ?? "-") file=\(fileName) size=\(fileData.count)")
        return try await apiClient.uploadState(
            romId: romId,
            emulator: emulator,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    func updateState(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        logger.info("☁️ Updating state id=\(id) size=\(fileData.count)")
        return try await apiClient.updateState(
            id: id,
            emulator: emulator,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    func downloadState(id: Int) async throws -> Data {
        logger.info("☁️ Downloading state id=\(id)")
        return try await apiClient.downloadState(id: id)
    }

    func deleteStates(ids: [Int]) async throws {
        logger.info("☁️ Deleting states \(ids)")
        try await apiClient.deleteStates(ids: ids)
    }
}
