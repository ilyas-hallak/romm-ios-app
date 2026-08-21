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
    
    init(apiClient: PRommAPIClient = RommAPIClient.shared) {
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
            // ROM favorites are managed through the Favourites collection (usually ID 2)
            // First, get the current Favourites collection to get existing ROM IDs
            logger.debug("📱 Fetching favorites collection...")
            let favouritesCollection = try await apiClient.get("api/collections/2", responseType: CollectionSchema.self)
            logger.debug("📱 Got favorites collection with \(favouritesCollection.romIds.count) ROMs")
            var currentRomIds = Array(favouritesCollection.romIds)
            
            // Add or remove the ROM from the favorites collection
            if isFavorite {
                if !currentRomIds.contains(romId) {
                    currentRomIds.append(romId)
                }
            } else {
                currentRomIds.removeAll { $0 == romId }
            }
            
            // Create multipart form data manually
            let boundary = "----RommAppBoundary\(UUID().uuidString)"
            var formData = Data()
            
            // Helper function to add form field
            func addFormField(_ name: String, _ value: String) {
                formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                formData.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                formData.append("\(value)\r\n".data(using: .utf8)!)
            }
            
            // Add form fields
            addFormField("name", favouritesCollection.name)
            addFormField("description", favouritesCollection.description ?? "")
            addFormField("url_cover", favouritesCollection.urlCover ?? "")
            addFormField("rom_ids", "[\(currentRomIds.map(String.init).joined(separator: ","))]")
            
            // Close boundary
            formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            // Make request via the API client with custom multipart data
            let isPublicValue = favouritesCollection.isPublic ?? false ? "true" : "false"
            let path = "api/collections/2?is_public=\(isPublicValue)&remove_cover=false"
            logger.debug("📱 Making multipart request to: \(path)")
            logger.debug("📱 Sending ROM IDs: [\(currentRomIds.map(String.init).joined(separator: ","))]")
            
            _ = try await apiClient.multipartRequest(
                path: path,
                method: .put,
                boundary: boundary,
                formData: formData,
                additionalHeaders: nil
            )
            
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
            // Get the Favourites collection to check if ROM is included
            let favouritesCollection = try await apiClient.get("api/collections/2", responseType: CollectionSchema.self)
            let isFavorite = favouritesCollection.romIds.contains(romId)
            
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
}
