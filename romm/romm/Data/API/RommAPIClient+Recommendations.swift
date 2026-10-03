//
//  RommAPIClient+Recommendations.swift
//  romm
//

import Foundation

// MARK: - Recommendations API Wrapper
extension RommAPIClient {
    /// `refresh` is intentionally not exposed here: pull to refresh can use the
    /// cached recommendations, the server already reranks them from live play history.
    func getRecommendations(limit: Int) async throws -> [RecommendedRomSchema] {
        let path = withQuery("api/recommendations", [
            ("limit", String(limit))
        ])
        let data = try await get(path)
        // Lenient so one malformed item doesn't hide the whole row.
        return try JSONDecoder().decode(LossyArray<RecommendedRomSchema>.self, from: data).elements
    }
}
