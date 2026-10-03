//
//  RommAPIClient+Recommendations.swift
//  romm
//

import Foundation

// MARK: - Recommendations API Wrapper
extension RommAPIClient {
    /// `refresh` is intentionally not exposed here: pull to refresh can use the
    /// cached recommendations, the server already reranks them from live play history.
    func getRecommendations(limit: Int = 20) async throws -> [RecommendedRomSchema] {
        let path = withQuery("api/recommendations", [
            ("limit", String(limit))
        ])
        return try await get(path, responseType: [RecommendedRomSchema].self)
    }
}
