//
//  TestConnectionUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation

class TestConnectionUseCase {
    private let connectionManager: PSFTPConnectionManager
    
    init(connectionManager: PSFTPConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    func execute(_ connection: SFTPConnection) async -> Bool {
        let status = await connectionManager.checkConnectionStatus(for: connection, forceRefresh: true)
        return status == .connected
    }
    
    func executeWithCredentials(_ connection: SFTPConnection, credentials: SFTPCredentials) async -> Bool {
        do {
            return try await connectionManager.testConnection(connection, credentials: credentials)
        } catch {
            return false
        }
    }
    
    func executeWithCredentialsThrows(_ connection: SFTPConnection, credentials: SFTPCredentials) async throws -> Bool {
        try await connectionManager.testConnection(connection, credentials: credentials)
    }
}