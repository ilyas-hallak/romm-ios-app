//
//  PlatformsRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

class PlatformsRepository: PPlatformsRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient
    
    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }
    
    func getPlatforms() async throws -> [Platform] {
        logger.info("Getting platforms with authenticated request...")
        
        do {
            let apiPlatforms = try await apiClient.getPlatforms()
            let domainPlatforms = apiPlatforms.mapToDomain()
            
            logger.info("Retrieved \(domainPlatforms.count) platforms")
            return domainPlatforms
        } catch {
            logger.error("Error getting platforms: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
    
    func addPlatform(name: String, slug: String) async throws -> Platform {
        logger.info("Adding platform: \(name)")
        
        do {
            let apiPlatform = try await apiClient.addPlatform(name: name, slug: slug)
            let domainPlatform = PlatformMapper.mapFromAPI(apiPlatform)
            
            logger.info("Platform added: \(domainPlatform.name)")
            return domainPlatform
        } catch {
            logger.error("Error adding platform: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
    
    func deletePlatform(id: Int) async throws {
        logger.info("Deleting platform ID: \(id)")
        
        do {
            _ = try await apiClient.deletePlatform(id: id)
            logger.info("Platform deleted: \(id)")
        } catch {
            logger.error("Error deleting platform: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
}