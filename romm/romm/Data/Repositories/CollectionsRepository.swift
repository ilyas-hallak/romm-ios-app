//
//  CollectionsRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 10.08.25.
//

import Foundation

class CollectionsRepository: PCollectionsRepository {
    private let apiClient: PRommAPIClient
    private let logger = Logger.data
    
    init(apiClient: PRommAPIClient = RommAPIClient.shared) {
        self.apiClient = apiClient
    }
    
    func getCollections(limit: Int? = nil, offset: Int? = nil) async throws -> [Collection] {
        logger.info("Getting collections with limit: \(limit ?? -1), offset: \(offset ?? 0)")
        
        do {
            let apiCollections = try await apiClient.getCollections(limit: limit, offset: offset)
            let domainCollections = apiCollections.mapToDomain()
            
            logger.info("Retrieved \(domainCollections.count) collections")
            return domainCollections
        } catch {
            logger.error("Error getting collections: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
    
    func getVirtualCollections(type: String, limit: Int? = nil) async throws -> [VirtualCollection] {
        logger.info("Getting virtual collections of type: \(type)")
        
        do {
            let apiCollections = try await apiClient.getVirtualCollections(type: type, limit: limit)
            let domainCollections = apiCollections.mapVirtualToDomain()
            
            logger.info("Retrieved \(domainCollections.count) virtual collections")
            return domainCollections
        } catch {
            logger.error("Error getting virtual collections: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
    
    func getCollection(id: Int) async throws -> Collection {
        logger.info("Getting collection details for ID: \(id)")
        
        do {
            let apiCollection = try await apiClient.getCollection(id: id)
            let domainCollection = CollectionMapper.mapFromAPI(apiCollection)
            
            logger.info("Retrieved collection: \(domainCollection.name)")
            return domainCollection
        } catch {
            logger.error("Error getting collection details: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
    
    func getVirtualCollection(id: String) async throws -> VirtualCollection {
        logger.info("Getting virtual collection details for ID: \(id)")
        
        do {
            let apiCollection = try await apiClient.getVirtualCollection(id: id)
            let domainCollection = CollectionMapper.mapVirtualFromAPI(apiCollection)
            
            logger.info("Retrieved virtual collection: \(domainCollection.name)")
            return domainCollection
        } catch {
            logger.error("Error getting virtual collection details: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
    
    func createCollection(data: CreateCollectionData) async throws -> Collection {
        logger.info("Creating collection: \(data.name)")
        
        do {
            // Use the API client wrapper method with parameters
            let createdCollection = try await apiClient.createCollection(
                name: data.name,
                description: data.description,
                isPublic: data.isPublic,
                isFavorite: false,
                artwork: data.artworkURL
            )
            
            let domainCollection = CollectionMapper.mapFromAPI(createdCollection)
            logger.info("✅ Collection created - API name: '\(createdCollection.name)', Domain name: '\(domainCollection.name)', ID: \(domainCollection.id)")
            return domainCollection
            
        } catch {
            logger.error("❌ Error creating collection: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
    
    func updateCollection(
        id: Int,
        name: String,
        description: String,
        isPublic: Bool,
        romIds: [Int]
    ) async throws -> Collection {
        logger.info("Updating collection \(id) with \(romIds.count) ROMs")
        
        do {
            let updatedApiCollection = try await apiClient.updateCollection(
                id: id,
                name: name,
                description: description,
                isPublic: isPublic,
                romIds: romIds,
                artwork: nil
            )
            
            let domainCollection = CollectionMapper.mapFromAPI(updatedApiCollection)
            logger.info("✅ Collection updated: id=\(domainCollection.id), name='\(domainCollection.name)', romCount=\(domainCollection.romCount)")
            return domainCollection
        } catch {
            logger.error("❌ Error updating collection: \(error)")
            throw error
        }
    }
    
    func deleteCollection(id: Int) async throws {
        logger.info("Deleting collection: \(id)")
        
        do {
            // Use the API client wrapper method
            _ = try await apiClient.deleteCollection(id: id)
            logger.info("✅ Collection deleted: \(id)")
        } catch {
            logger.error("❌ Error deleting collection: \(error)")
            // Re-throw the original error to preserve detailed error information
            throw error
        }
    }
}

enum CollectionError: Error, LocalizedError {
    case networkError
    case collectionNotFound
    case invalidCollectionId
    case invalidCollectionName
    case creationFailed
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection error"
        case .collectionNotFound:
            return "Collection not found"
        case .invalidCollectionId:
            return "Invalid collection ID"
        case .invalidCollectionName:
            return "Collection name cannot be empty"
        case .creationFailed:
            return "Failed to create collection"
        }
    }
}
