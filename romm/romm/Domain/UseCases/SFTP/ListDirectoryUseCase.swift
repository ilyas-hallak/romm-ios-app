//
//  ListDirectoryUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation

class ListDirectoryUseCase {
    private let connectionManager: PSFTPConnectionManager
    
    init(connectionManager: PSFTPConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    func execute(at path: String, connection: SFTPConnection) async throws -> [SFTPDirectoryItem] {
        return try await connectionManager.listDirectory(at: path, connection: connection)
    }
}