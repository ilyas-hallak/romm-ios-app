import Foundation

protocol PListServerSavesUseCase {
    func execute(romId: Int) async throws -> [SaveSchema]
}

protocol PUploadSaveUseCase {
    func execute(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, overwrite: Bool?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
}

protocol PUpdateSaveUseCase {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
}

protocol PDownloadSaveUseCase {
    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data
}

protocol PConfirmSaveDownloadUseCase {
    func execute(id: Int, deviceId: String) async throws -> SaveSchema
}

final class ListServerSavesUseCase: PListServerSavesUseCase {
    private let repository: PSavesRepository
    init(repository: PSavesRepository) { self.repository = repository }
    func execute(romId: Int) async throws -> [SaveSchema] {
        guard romId > 0 else { throw RomError.invalidRomId }
        return try await repository.listServerSaves(romId: romId)
    }
}

final class UploadSaveUseCase: PUploadSaveUseCase {
    private let repository: PSavesRepository
    init(repository: PSavesRepository) { self.repository = repository }
    func execute(romId: Int, emulator: String?, slot: String?, deviceId: String?, sessionId: String?, autocleanup: Bool?, overwrite: Bool?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        guard romId > 0 else { throw RomError.invalidRomId }
        return try await repository.uploadSave(
            romId: romId,
            emulator: emulator,
            slot: slot,
            deviceId: deviceId,
            sessionId: sessionId,
            autocleanup: autocleanup,
            overwrite: overwrite,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }
}

final class UpdateSaveUseCase: PUpdateSaveUseCase {
    private let repository: PSavesRepository
    init(repository: PSavesRepository) { self.repository = repository }
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        try await repository.updateSave(
            id: id,
            emulator: emulator,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }
}

final class DownloadSaveUseCase: PDownloadSaveUseCase {
    private let repository: PSavesRepository
    init(repository: PSavesRepository) { self.repository = repository }
    func execute(id: Int, deviceId: String?, sessionId: String?) async throws -> Data {
        try await repository.downloadSave(id: id, deviceId: deviceId, sessionId: sessionId)
    }
}

/// Tells the server this device now has the save's current content. Meant to be
/// called right after a downloaded save is written locally, never before, so a
/// crash mid-write never confirms content that was never actually saved.
final class ConfirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase {
    private let repository: PSavesRepository
    init(repository: PSavesRepository) { self.repository = repository }
    func execute(id: Int, deviceId: String) async throws -> SaveSchema {
        try await repository.confirmDownload(id: id, deviceId: deviceId)
    }
}
