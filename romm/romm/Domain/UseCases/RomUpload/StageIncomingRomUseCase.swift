//
//  StageIncomingRomUseCase.swift
//  romm
//

import Foundation

nonisolated final class StageIncomingRomUseCase: Sendable {
    private let repository: PIncomingRomFileRepository

    init(repository: PIncomingRomFileRepository) {
        self.repository = repository
    }

    @concurrent
    func execute(url: URL) async throws -> StagedRomFile {
        try repository.stage(url: url)
    }
}
