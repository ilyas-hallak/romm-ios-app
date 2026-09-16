import Foundation

final class SavesRepository: PSavesRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient

    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }

    func listServerSaves(romId: Int) async throws -> [SaveSchema] {
        try await apiClient.getSaves(romId: romId)
    }

    func uploadSave(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        logger.info("☁️ Uploading save romId=\(romId) emulator=\(emulator ?? "-") slot=\(slot ?? "-") device=\(deviceId ?? "-") size=\(fileData.count)")
        return try await apiClient.uploadSave(
            romId: romId,
            emulator: emulator,
            slot: slot,
            deviceId: deviceId,
            sessionId: sessionId,
            autocleanup: autocleanup,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    func updateSave(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        logger.info("☁️ Updating save id=\(id) size=\(fileData.count)")
        return try await apiClient.updateSave(
            id: id,
            emulator: emulator,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    func downloadSave(id: Int, deviceId: String?, sessionId: String?) async throws -> Data {
        logger.info("☁️ Downloading save id=\(id) device=\(deviceId ?? "-")")
        return try await apiClient.downloadSave(id: id, deviceId: deviceId, sessionId: sessionId)
    }

    func deleteSaves(ids: [Int]) async throws {
        logger.info("☁️ Deleting saves \(ids)")
        try await apiClient.deleteSaves(ids: ids)
    }

    func confirmDownload(id: Int, deviceId: String) async throws -> SaveSchema {
        logger.info("☁️ Confirming download save id=\(id) device=\(deviceId)")
        return try await apiClient.confirmSaveDownloaded(id: id, deviceId: deviceId)
    }
}
