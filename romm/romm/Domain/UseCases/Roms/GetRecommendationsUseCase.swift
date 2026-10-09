//
//  GetRecommendationsUseCase.swift
//  romm
//

import Foundation

class GetRecommendationsUseCase {
    private let romsRepository: PRomsRepository

    init(romsRepository: PRomsRepository) {
        self.romsRepository = romsRepository
    }

    func execute(limit: Int = 20) async throws -> [Recommendation] {
        return try await romsRepository.getRecommendations(limit: limit)
    }
}
