//
//  PRomsRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

protocol PRomsRepository {
    func getRoms(platformId: Int?, searchTerm: String?, limit: Int, offset: Int, char: String?, orderBy: String?, orderDir: String?, collectionId: Int?) async throws -> PaginatedRomsResponse
    
    // Clean method for filtered ROMs using RomFilters object
    func getRomsWithFilters(
        platformId: Int?,
        searchTerm: String?,
        limit: Int,
        offset: Int,
        char: String?,
        orderBy: String?,
        orderDir: String?,
        collectionId: Int?,
        filters: RomFilters
    ) async throws -> PaginatedRomsResponse
    func getRomDetails(id: Int) async throws -> RomDetails
    func toggleRomFavorite(romId: Int, isFavorite: Bool) async throws
    func isRomFavorite(romId: Int) async throws -> Bool
    func updateLastPlayed(romId: Int) async throws
    func searchRoms(query: String) async throws -> [Rom]
    func searchRomsLegacy(query: String) async throws -> [Rom]
    func getRecommendations(limit: Int) async throws -> [Recommendation]
}