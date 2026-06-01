//
//  RommAPIClient+Roms.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

// MARK: - ROMs API Wrapper
extension RommAPIClient {
    func getRoms(
        searchTerm: String? = nil,
        platformId: Int? = nil,
        limit: Int = 50
    ) async throws -> CustomLimitOffsetPageSimpleRomSchema {
        let path = withQuery("api/roms", [
            ("search_term", searchTerm),
            ("platform_ids", platformId.map(String.init)),
            ("limit", String(limit))
        ])
        return try await get(path, responseType: CustomLimitOffsetPageSimpleRomSchema.self)
    }

    func getRomsWithFilters(
        searchTerm: String? = nil,
        platformId: Int? = nil,
        collectionId: Int? = nil,
        limit: Int = 50,
        offset: Int? = nil,
        withCharIndex: Bool? = nil,
        orderBy: String? = nil,
        orderDir: String? = nil,
        filters: RomFilters
    ) async throws -> CustomLimitOffsetPageSimpleRomSchema {
        let groupByMetaId = GetGroupRomsUseCase().execute()
        let path = withQuery("api/roms", [
            ("with_char_index", withCharIndex.map(String.init)),
            ("search_term", searchTerm),
            ("platform_ids", platformId.map(String.init)),
            ("collection_id", collectionId.map(String.init)),
            ("matched", filters.matched.map(String.init)),
            ("favorite", filters.favourite.map(String.init)),
            ("duplicate", filters.duplicate.map(String.init)),
            ("playable", filters.playable.map(String.init)),
            ("missing", filters.missing.map(String.init)),
            ("has_ra", filters.hasRa.map(String.init)),
            ("verified", filters.verified.map(String.init)),
            ("last_played", filters.lastPlayed.map(String.init)),
            ("group_by_meta_id", groupByMetaId ? "true" : "false"),
            ("genres", filters.selectedGenre),
            ("franchises", filters.selectedFranchise),
            ("collections", filters.selectedCollection),
            ("companies", filters.selectedCompany),
            ("age_ratings", filters.selectedAgeRating),
            ("statuses", filters.selectedStatus),
            ("regions", filters.selectedRegion),
            ("languages", filters.selectedLanguage),
            ("genres_logic", filters.selectedGenre != nil ? "any" : nil),
            ("franchises_logic", filters.selectedFranchise != nil ? "any" : nil),
            ("collections_logic", filters.selectedCollection != nil ? "any" : nil),
            ("companies_logic", filters.selectedCompany != nil ? "any" : nil),
            ("age_ratings_logic", filters.selectedAgeRating != nil ? "any" : nil),
            ("statuses_logic", filters.selectedStatus != nil ? "any" : nil),
            ("regions_logic", filters.selectedRegion != nil ? "any" : nil),
            ("languages_logic", filters.selectedLanguage != nil ? "any" : nil),
            ("order_by", orderBy),
            ("order_dir", orderDir),
            ("limit", String(limit)),
            ("offset", offset.map(String.init))
        ])
        return try await get(path, responseType: CustomLimitOffsetPageSimpleRomSchema.self)
    }

    func getRomDetails(id: Int) async throws -> DetailedRomSchema {
        return try await get("api/roms/\(id)", responseType: DetailedRomSchema.self)
    }

    func searchRomsWithOpenAPI(query: String) async throws -> CustomLimitOffsetPageSimpleRomSchema {
        logger.info("🔍 Search: Searching for '\(query)'")
        let path = withQuery("api/roms", [
            ("search_term", query),
            ("limit", "50"),
            ("offset", "0")
        ])
        let result = try await get(path, responseType: CustomLimitOffsetPageSimpleRomSchema.self)
        logger.info("🔍 Search: Found \(result.items.count) ROMs out of \(result.total ?? 0) total")
        return result
    }

    func updateRomLastPlayed(id: Int) async throws -> RomUserSchema {
        let body = BodyUpdateRomUserApiRomsIdPropsPut(
            updateLastPlayed: true,
            removeLastPlayed: false
        )
        return try await put("api/roms/\(id)/props", body: body, responseType: RomUserSchema.self)
    }

    func getRomManual(romId: Int) async throws -> Manual? {
        let romDetails = try await get("api/roms/\(romId)", responseType: DetailedRomSchema.self)

        guard let pathManual = romDetails.pathManual, !pathManual.isEmpty else {
            return nil
        }

        guard let serverURL = tokenProvider.getServerURL() else {
            throw APIClientError.noConfiguration
        }

        let completePath = "assets/romm/resources/\(pathManual.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        let fullManualURL = "\(serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(completePath)"

        logger.debug("ROM Details pathManual: \(pathManual)")
        logger.debug("Full manual URL: \(fullManualURL)")

        return Manual(
            id: 0,
            romId: romId,
            title: "Manual",
            url: fullManualURL,
            fileName: "manual.pdf",
            sizeBytes: nil
        )
    }

    func getManualPDFData(manualURL: String) async throws -> Data {
        guard let url = URL(string: manualURL) else {
            throw APIClientError.invalidURL(manualURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 60.0

        logger.debug("Attempting PDF download from: \(manualURL)")

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIClientError.networkError(URLError(.badServerResponse))
            }

            logger.debug("PDF Response status: \(httpResponse.statusCode), size: \(data.count) bytes")

            switch httpResponse.statusCode {
            case 200...299:
                if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String,
                   contentType.contains("text/html") {
                    let htmlContent = String(data: data, encoding: .utf8) ?? "HTML content"
                    logger.error("Received HTML instead of PDF: \(htmlContent.prefix(200))")
                    throw APIClientError.invalidResponse(200, "Received HTML instead of PDF - authentication may have failed")
                }
                return data
            case 401, 403:
                throw APIClientError.authenticationRequired
            default:
                let msg = String(data: data, encoding: .utf8) ?? "PDF download failed"
                logger.error("PDF download failed (\(httpResponse.statusCode)): \(msg)")
                throw APIClientError.invalidResponse(httpResponse.statusCode, msg)
            }
        } catch let error as URLError {
            logger.logNetworkError(method: "GET", url: manualURL, error: error)
            throw APIClientError.networkError(error)
        } catch let error as APIClientError {
            throw error
        } catch {
            logger.error("Unexpected error during PDF download: \(error)")
            throw APIClientError.networkError(error)
        }
    }
}