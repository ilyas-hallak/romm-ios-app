//
//  SaveScanCredentialsUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 12.09.26.
//

import Foundation

class SaveScanCredentialsUseCase {
    private let scanRepository: PScanRepository

    init(scanRepository: PScanRepository) {
        self.scanRepository = scanRepository
    }

    func execute(username: String, password: String) throws {
        try scanRepository.saveScanCredentials(username: username, password: password)
    }
}
