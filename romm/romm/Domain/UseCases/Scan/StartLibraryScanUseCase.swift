//
//  StartLibraryScanUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

class StartLibraryScanUseCase {
    private let scanRepository: PScanRepository

    init(scanRepository: PScanRepository) {
        self.scanRepository = scanRepository
    }

    func execute(type: LibraryScanType, platformIds: [Int]) async throws -> AsyncStream<LibraryScanEvent> {
        return try await scanRepository.startScan(type: type, platformIds: platformIds)
    }
}
