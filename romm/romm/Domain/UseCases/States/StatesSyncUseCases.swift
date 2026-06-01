import Foundation

protocol PListServerStatesUseCase {
    func execute(romId: Int) async throws -> [StateSchema]
}

protocol PUploadStateUseCase {
    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema
}

protocol PUpdateStateUseCase {
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema
}

protocol PDownloadStateUseCase {
    func execute(id: Int) async throws -> Data
}

final class ListServerStatesUseCase: PListServerStatesUseCase {
    private let repository: PStatesRepository
    init(repository: PStatesRepository) { self.repository = repository }
    func execute(romId: Int) async throws -> [StateSchema] {
        guard romId > 0 else { throw RomError.invalidRomId }
        return try await repository.listServerStates(romId: romId)
    }
}

final class UploadStateUseCase: PUploadStateUseCase {
    private let repository: PStatesRepository
    init(repository: PStatesRepository) { self.repository = repository }
    func execute(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        guard romId > 0 else { throw RomError.invalidRomId }
        return try await repository.uploadState(
            romId: romId,
            emulator: emulator,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }
}

final class UpdateStateUseCase: PUpdateStateUseCase {
    private let repository: PStatesRepository
    init(repository: PStatesRepository) { self.repository = repository }
    func execute(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema {
        try await repository.updateState(
            id: id,
            emulator: emulator,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }
}

final class DownloadStateUseCase: PDownloadStateUseCase {
    private let repository: PStatesRepository
    init(repository: PStatesRepository) { self.repository = repository }
    func execute(id: Int) async throws -> Data {
        try await repository.downloadState(id: id)
    }
}
