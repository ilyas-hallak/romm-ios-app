//
//  StopLibraryScanUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

class StopLibraryScanUseCase {
    private let scanRepository: PScanRepository

    init(scanRepository: PScanRepository) {
        self.scanRepository = scanRepository
    }

    func execute() async throws {
        try await scanRepository.stopScan()
    }
}
