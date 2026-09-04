//
//  ManualRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 13.08.25.
//

import Foundation

class ManualRepository: PManualRepository {
    private let apiClient: PRommAPIClient
    private let logger = Logger.data
    
    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }
    
    func loadManual(for romId: Int) async throws -> Manual? {
        return try await apiClient.getRomManual(romId: romId)
    }
    
    func getManualPDFData(for romId: Int) async throws -> Data? {
        // First get the manual to check if it exists and get the URL
        guard let manual = try await loadManual(for: romId) else {
            return nil
        }
        
        // Download PDF data from the manual URL
        return try await apiClient.getManualPDFData(manualURL: manual.url)
    }
}
