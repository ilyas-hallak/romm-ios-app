//
//  DiscardStagedRomUseCase.swift
//  romm
//

import Foundation

/// Deletes a staged file the user did not upload after all, for example when
/// the upload sheet is dismissed without picking a platform.
class DiscardStagedRomUseCase {
    private let repository: PIncomingRomFileRepository

    init(repository: PIncomingRomFileRepository) {
        self.repository = repository
    }

    func execute(_ file: StagedRomFile) {
        repository.removeStagedFile(relativePath: file.relativePath)
    }
}
