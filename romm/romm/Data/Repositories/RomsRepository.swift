//
//  RomsRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

class RomsRepository: PRomsRepository {
    private let apiClient: PRommAPIClient
    private let logger = Logger.data
    
    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }
    
    func getRoms(platformId: Int?, searchTerm: String?, limit: Int, offset: Int = 0, char: String? = nil, orderBy: String? = nil, orderDir: String? = nil, collectionId: Int? = nil) async throws -> PaginatedRomsResponse {
        // Keep the old implementation for backward compatibility 
        // This uses OpenAPI but without filter parameters
        logger.info("🕹️ Getting ROMs (legacy) - Platform: \(platformId?.description ?? "all"), Collection: \(collectionId?.description ?? "none"), Search: \(searchTerm ?? "none"), Limit: \(limit), Offset: \(offset), Char: \(char ?? "none")")
        
        do {
            let romsPage = try await apiClient.getRomsWithFilters(
                searchTerm: searchTerm,
                platformId: platformId,
                collectionId: collectionId,
                limit: limit,
                offset: offset,
                withCharIndex: char != nil ? false : true,
                orderBy: orderBy ?? "name",
                orderDir: orderDir ?? "asc",
                filters: .empty // No filter parameters - keep it simple
            )

            let domainRoms = romsPage.items.mapToDomain()

            let paginatedResponse = PaginatedRomsResponse(
                roms: domainRoms,
                total: romsPage.total ?? 0,
                limit: romsPage.limit ?? limit,
                offset: romsPage.offset ?? offset,
                charIndex: romsPage.charIndex
            )
            
            logger.info("✅ Retrieved \(domainRoms.count) ROMs (Total: \(paginatedResponse.total), HasMore: \(paginatedResponse.hasMore))")
            return paginatedResponse
        } catch {
            logger.error("❌ Error getting ROMs: \(error)")
            throw RomError.networkError
        }
    }
    
    func getRomsWithFilters(
        platformId: Int?,
        searchTerm: String?,
        limit: Int,
        offset: Int = 0,
        char: String? = nil,
        orderBy: String? = nil,
        orderDir: String? = nil,
        collectionId: Int? = nil,
        filters: RomFilters
    ) async throws -> PaginatedRomsResponse {
        logger.info("🕹️ Getting ROMs with filters - Platform: \(platformId?.description ?? "all"), Collection: \(collectionId?.description ?? "none"), Search: \(searchTerm ?? "none"), Limit: \(limit), Offset: \(offset), Char: \(char ?? "none")")
        logger.info("🔧 Filters active: \(filters.hasActiveFilters)")
        
        do {
            // Use the clean OpenAPI facade with RomFilters object
            let romsPage = try await apiClient.getRomsWithFilters(
                searchTerm: searchTerm,
                platformId: platformId,
                collectionId: collectionId,
                limit: limit,
                offset: offset,
                withCharIndex: char != nil ? false : true, // Don't return char index when filtering by char
                orderBy: orderBy ?? "name",
                orderDir: orderDir ?? "asc",
                filters: filters
            )
            
            let domainRoms = romsPage.items.mapToDomain()

            let paginatedResponse = PaginatedRomsResponse(
                roms: domainRoms,
                total: romsPage.total ?? 0,
                limit: romsPage.limit ?? limit,
                offset: romsPage.offset ?? offset,
                charIndex: romsPage.charIndex
            )
            
            logger.info("✅ Retrieved \(domainRoms.count) filtered ROMs (Total: \(paginatedResponse.total), HasMore: \(paginatedResponse.hasMore))")
            return paginatedResponse
        } catch {
            logger.error("❌ Error getting filtered ROMs: \(error)")
            throw RomError.networkError
        }
    }

    func getRomDetails(id: Int) async throws -> RomDetails {
        logger.info("📄 Getting ROM details for ID: \(id)")
        
        do {
            let apiRom = try await apiClient.get("api/roms/\(id)", responseType: DetailedRomSchema.self)
            let domainRom = RomMapper.mapDetailsFromAPI(apiRom)
            
            logger.info("✅ Retrieved ROM details: \(domainRom.name)")
            return domainRom
        } catch {
            logger.error("❌ Error getting ROM details: \(error)")
            throw RomError.networkError
        }
    }
    
    func toggleRomFavorite(romId: Int, isFavorite: Bool) async throws {
        logger.info("❤️ Toggling favorite for ROM \(romId): \(isFavorite)")
        
        do {
            let collection = isFavorite
                ? try await favouritesCollection()
                : try await findFavouritesCollection()

            guard let collection else {
                // Nothing to remove the ROM from, so the desired state is already reached.
                logger.info("✅ No favourites collection, ROM \(romId) is not a favourite anyway")
                return
            }

            _ = isFavorite
                ? try await apiClient.addRomsToCollection(id: collection.id, romIds: [romId])
                : try await apiClient.removeRomsFromCollection(id: collection.id, romIds: [romId])

            logger.info("✅ ROM favorite toggled: \(romId)")
        } catch {
            logger.error("❌ Error toggling ROM favorite: \(error)")
            
            // Check if it's already a RomError, if so, rethrow it
            if let romError = error as? RomError {
                throw romError
            }
            
            // For other errors, provide more context
            if error.localizedDescription.contains("The Internet connection appears to be offline") {
                logger.error("❌ Network connectivity issue")
            } else if error.localizedDescription.contains("401") || error.localizedDescription.contains("403") {
                logger.error("❌ Authentication issue")
            }
            
            throw RomError.networkError
        }
    }
    
    func updateLastPlayed(romId: Int) async throws {
        logger.info("⏱️ Updating last_played for ROM \(romId)")
        do {
            _ = try await apiClient.updateRomLastPlayed(id: romId)
            logger.info("✅ last_played updated for ROM \(romId)")
        } catch {
            logger.error("❌ Failed to update last_played for ROM \(romId): \(error)")
            throw RomError.networkError
        }
    }

    func isRomFavorite(romId: Int) async throws -> Bool {
        logger.info("🔍 Checking favorite status for ROM \(romId)")
        
        do {
            guard let collection = try await findFavouritesCollection() else {
                logger.info("ℹ️ No favourites collection yet, treating ROM as not favourite")
                return false
            }
            let isFavorite = collection.romIds.contains(romId)
            
            logger.info("✅ ROM \(romId) favorite status: \(isFavorite)")
            return isFavorite
        } catch {
            logger.error("❌ Error checking ROM favorite status: \(error)")
            logger.error("❌ Error details: \(String(describing: error))")
            
            // Check for specific error types to provide better logging
            if let apiError = error as? APIClientError {
                switch apiError {
                case .invalidResponse(let code, let message):
                    logger.error("❌ API returned status \(code): \(message)")
                case .networkError(let networkError):
                    logger.error("❌ Network error: \(networkError.localizedDescription)")
                case .noConfiguration:
                    logger.error("❌ No API configuration found")
                case .noCredentials:
                    logger.error("❌ No credentials available")
                default:
                    logger.error("❌ Other API error: \(apiError)")
                }
            }
            
            // If we can't check favorites, assume false rather than throwing
            // This prevents crashes in the UI
            return false
        }
    }
    
    func searchRoms(query: String) async throws -> [Rom] {
        logger.info("🔍 Direct API Search: Searching ROMs with query: '\(query)'")
        
        do {
            // Use OpenAPI directly for search
            let response = try await apiClient.searchRomsWithOpenAPI(query: query)
            let domainRoms = response.items.mapToDomain()
            
            logger.info("✅ Direct API Search: Found \(domainRoms.count) ROMs out of \(response.total ?? 0) total matches")
            return domainRoms
        } catch {
            logger.error("❌ Direct API Search failed: \(error)")
            throw RomError.networkError
        }
    }
    
    func searchRomsLegacy(query: String) async throws -> [Rom] {
        logger.info("🔍 Legacy Search: Searching ROMs with query: '\(query)'")
        
        // Search ROMs using the normal getRoms API with search term
        let response = try await getRoms(platformId: nil, searchTerm: query, limit: 50, offset: 0, collectionId: nil)
        
        logger.info("🔍 Legacy Search completed: found \(response.roms.count) ROMs out of \(response.total) total matches")
        return response.roms
    }

    // MARK: - Favourites Collection

    /// Finds the user's own favourites collection, identified by the `is_favorite` flag.
    /// The collection has no fixed ID, so it cannot be hardcoded. The owner has to be
    /// checked as well, because the endpoint also returns other users' public collections
    /// and writing to one of those fails with a permission error.
    private func findFavouritesCollection() async throws -> CollectionSchema? {
        let currentUserId = try await apiClient.getCurrentUser().id
        let collections = try await apiClient.getCollections(limit: nil, offset: nil)
        return collections.first { $0.isFavorite == true && $0.userId == currentUserId }
    }

    /// Same as `findFavouritesCollection`, but creates the collection when it is missing.
    /// RomM never creates it on its own, neither during setup nor when a user is added, so
    /// the first favourite has to. The name matches the one the web frontend uses so both
    /// clients end up on the same collection.
    private func favouritesCollection() async throws -> CollectionSchema {
        if let existing = try await findFavouritesCollection() {
            return existing
        }

        logger.info("❤️ No favourites collection on the server yet, creating one")
        return try await apiClient.createCollection(
            name: "Favorites",
            description: "",
            isPublic: false,
            isFavorite: true,
            artwork: nil
        )
    }
}
