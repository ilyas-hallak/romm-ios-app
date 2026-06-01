import Foundation

protocol PListServerSavesUseCase {
    func execute(romId: Int) async throws -> [SaveSchema]
}

protocol PUploadSaveUseCase {
    func execute(romId: Int, emulator: String?, slot: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
}

protocol PUpdateSaveUseCase {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema
}

protocol PDownloadSaveUseCase {
    func execute(id: Int) async throws -> Data
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
    func execute(romId: Int, emulator: String?, slot: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        guard romId > 0 else { throw RomError.invalidRomId }
        return try await repository.uploadSave(
            romId: romId,
            emulator: emulator,
            slot: slot,
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
    func execute(id: Int) async throws -> Data {
        try await repository.downloadSave(id: id)
    }
}
