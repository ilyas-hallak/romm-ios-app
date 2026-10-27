//
//  ClearConnectionCacheUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation

class ClearConnectionCacheUseCase {
    private let connectionManager: PSFTPConnectionManager
    
    init(connectionManager: PSFTPConnectionManager) {
        self.connectionManager = connectionManager
    }
    
    func execute() async {
        await connectionManager.clearCache()
    }

    func execute(for connection: SFTPConnection) async {
        await connectionManager.clearCache(for: connection)
    }
}