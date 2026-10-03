//
//  StageIncomingRomUseCase.swift
//  romm
//

import Foundation

class StageIncomingRomUseCase {
    private let repository: PIncomingRomFileRepository

    init(repository: PIncomingRomFileRepository) {
        self.repository = repository
    }

    func execute(url: URL) throws -> StagedRomFile {
        try repository.stage(url: url)
    }
}
