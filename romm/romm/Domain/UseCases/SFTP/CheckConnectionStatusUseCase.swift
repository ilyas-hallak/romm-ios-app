//
//  CheckConnectionStatusUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation

class CheckConnectionStatusUseCase {
    private let connectionManager: PSFTPConnectionManager
    
    init(connectionManager: PSFTPConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    func execute(for connection: SFTPConnection, forceRefresh: Bool = false) async -> ConnectionStatus {
        return await connectionManager.checkConnectionStatus(for: connection, forceRefresh: forceRefresh)
    }
    
    func executeForAllConnections(for connections: [SFTPConnection], forceRefresh: Bool = false) async {
        await connectionManager.checkAllConnectionStatuses(for: connections, forceRefresh: forceRefresh)
    }
}
