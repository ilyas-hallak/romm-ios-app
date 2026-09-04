//
//  StatsRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 16.11.25.
//

import Foundation

class StatsRepository: PStatsRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient

    init(apiClient: PRommAPIClient) {
        self.apiClient = apiClient
    }

    func getStats() async throws -> Stats {
        logger.info("Getting stats from API...")

        do {
            let apiStats = try await apiClient.getStats()
            let domainStats = StatsMapper.mapFromAPI(apiStats)

            logger.info("Retrieved stats: \(domainStats.roms) ROMs, \(domainStats.platforms) platforms")
            return domainStats
        } catch {
            logger.error("Error getting stats: \(error)")
            throw error
        }
    }
}
