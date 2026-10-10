//
//  GetRomUploadAvailabilityUseCase.swift
//  romm
//

import Foundation

class GetRomUploadAvailabilityUseCase {
    private let repository: PRomUploadRepository

    init(repository: PRomUploadRepository) {
        self.repository = repository
    }

    func execute() async -> RomUploadAvailability {
        await repository.availability()
    }
}
