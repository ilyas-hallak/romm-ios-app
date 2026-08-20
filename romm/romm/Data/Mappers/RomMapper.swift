//
//  RomMapper.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

struct RomMapper {
    static func mapFromAPI(_ apiRom: SimpleRomSchema) -> Rom {
        // Extract release year from metadata if available
        let releaseYear: Int? = {
            var timestamp: Int? =
            apiRom.igdbMetadata?.firstReleaseDate ??
            apiRom.ssMetadata?.firstReleaseDate ??
            apiRom.launchboxMetadata?.firstReleaseDate ??
            apiRom.metadatum.firstReleaseDate
            
            if let timestamp {
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let calendar = Calendar.current
                return calendar.component(.year, from: date)
            } else {
                return nil
            }
        }()
        
        // Aggregate metadata from all available sources
        let genres: [String] = aggregateMetadataArray([
            apiRom.metadatum.genres,
            apiRom.igdbMetadata?.genres,
            apiRom.ssMetadata?.genres,
            apiRom.mobyMetadata?.genres
        ])
        
        let franchises: [String] = aggregateMetadataArray([
            apiRom.metadatum.franchises,
            apiRom.igdbMetadata?.franchises,
            apiRom.ssMetadata?.franchises
        ])
        
        let companies: [String] = aggregateMetadataArray([
            apiRom.metadatum.companies,
            apiRom.igdbMetadata?.companies,
            apiRom.ssMetadata?.companies
        ])
        
        let ageRatings: [String] = aggregateAgeRatings(
            metadatumRatings: apiRom.metadatum.ageRatings,
            igdbRatings: apiRom.igdbMetadata?.ageRatings
        )
        
        return Rom(
            id: apiRom.id,
            name: apiRom.name ?? "Unknown ROM",
            slug: apiRom.slug ?? "",
            summary: apiRom.summary,
            platformId: apiRom.platformId,
            urlCover: apiRom.urlCover,
            releaseYear: releaseYear,
            isFavourite: false, // Resolved separately via the Favourites collection
            hasRetroAchievements: apiRom.raId != nil,
            isPlayable: !apiRom.missingFromFs,
            sizeBytes: apiRom.fsSizeBytes,
            createdAt: DateFormatter.iso8601Full.string(from: apiRom.createdAt),
            rating: apiRom.metadatum.averageRating,
            languages: apiRom.languages,
            regions: apiRom.regions,
            fileName: apiRom.files.first?.fileName ?? "",
            platformSlug: apiRom.platformSlug,
            genres: genres,
            franchises: franchises,
            companies: companies,
            ageRatings: ageRatings
        )
    }
    
    static func mapDetailsFromAPI(_ apiRom: DetailedRomSchema) -> RomDetails {
        // Aggregate release date from all available sources
        let releaseDate: Date? = {
            // Priority: metadatum -> igdbMetadata -> ssMetadata
            if let timestamp = apiRom.metadatum.firstReleaseDate {
                return Date(timeIntervalSince1970: TimeInterval(timestamp))
            } else if let timestamp = apiRom.igdbMetadata?.firstReleaseDate {
                return Date(timeIntervalSince1970: TimeInterval(timestamp))
            } else if let timestamp = apiRom.ssMetadata?.firstReleaseDate {
                return Date(timeIntervalSince1970: TimeInterval(timestamp))
            }
            return nil
        }()
        
        // Aggregate genres from all available sources
        let genres: [String] = aggregateMetadataArray([
            apiRom.metadatum.genres,
            apiRom.igdbMetadata?.genres,
            apiRom.ssMetadata?.genres,
            apiRom.mobyMetadata?.genres
        ])
        
        // Aggregate franchises from all available sources
        let franchises: [String] = aggregateMetadataArray([
            apiRom.metadatum.franchises,
            apiRom.igdbMetadata?.franchises,
            apiRom.ssMetadata?.franchises
        ])
        
        // Aggregate companies from all available sources
        let companies: [String] = aggregateMetadataArray([
            apiRom.metadatum.companies,
            apiRom.igdbMetadata?.companies,
            apiRom.ssMetadata?.companies
        ])
        
        // Aggregate game modes from all available sources
        let gameModes: [String] = aggregateMetadataArray([
            apiRom.metadatum.gameModes,
            apiRom.igdbMetadata?.gameModes,
            apiRom.ssMetadata?.gameModes
        ])
        
        // Aggregate age ratings from all available sources
        let ageRatings: [String] = aggregateAgeRatings(
            metadatumRatings: apiRom.metadatum.ageRatings,
            igdbRatings: apiRom.igdbMetadata?.ageRatings
        )
        
        // Aggregate ratings from all available sources
        let averageRating: Double? = {
            if let rating = apiRom.metadatum.averageRating {
                return rating
            } else if let ratingString = apiRom.igdbMetadata?.totalRating, let rating = Double(ratingString) {
                return rating
            } else if let ratingString = apiRom.igdbMetadata?.aggregatedRating, let rating = Double(ratingString) {
                return rating
            }
            return nil
        }()
        
        // Extract developer and publisher from companies array
        let developer: String? = companies.first
        let publisher: String? = companies.count > 1 ? companies[1] : companies.first
        
        return RomDetails(
            id: apiRom.id,
            name: apiRom.name ?? "Unknown ROM",
            fileName: apiRom.fsName,
            fsNameNoExt: apiRom.fsNameNoExt,
            fsName: apiRom.fsName,
            summary: apiRom.summary,
            urlCover: apiRom.urlCover,
            platformId: apiRom.platformId,
            isFavourite: false, // Will be loaded separately via user properties
            hasRetroAchievements: apiRom.raId != nil,
            genre: genres,
            developer: developer,
            publisher: publisher,
            releaseDate: releaseDate,
            pathManual: apiRom.pathManual,
            sizeBytes: apiRom.fsSizeBytes,
            sha1Hash: apiRom.sha1Hash,
            md5Hash: apiRom.md5Hash,
            crcHash: apiRom.crcHash,
            franchises: franchises,
            companies: companies,
            gameModes: gameModes,
            ageRatings: ageRatings,
            averageRating: averageRating,
            platformDisplayName: apiRom.platformDisplayName,
            siblings: apiRom.siblings.map { SiblingRom(
                id: $0.id,
                name: $0.name,
                fsNameNoTags: $0.fsNameNoTags,
                fsNameNoExt: $0.fsNameNoExt,
                sortComparator: $0.sortComparator
            )}
        )
    }
    
    // MARK: - Helper Methods for Metadata Aggregation
    
    /// Aggregates metadata arrays from multiple sources, prioritizing non-empty arrays
    /// and removing duplicates while preserving order
    private static func aggregateMetadataArray(_ sources: [[String]?]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        
        for source in sources {
            guard let items = source, !items.isEmpty else { continue }
            for item in items {
                let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedItem.isEmpty && !seen.contains(trimmedItem) {
                    result.append(trimmedItem)
                    seen.insert(trimmedItem)
                }
            }
        }
        
        return result
    }
    
    /// Aggregates age ratings from different metadata sources
    private static func aggregateAgeRatings(
        metadatumRatings: [String],
        igdbRatings: [IGDBAgeRating]?
    ) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        
        // Add from metadatum first (highest priority)
        for rating in metadatumRatings {
            let trimmedRating = rating.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedRating.isEmpty && !seen.contains(trimmedRating) {
                result.append(trimmedRating)
                seen.insert(trimmedRating)
            }
        }
        
        // Add from IGDB metadata if available
        if let igdbRatings = igdbRatings {
            for ageRating in igdbRatings {
                // Try to extract meaningful rating info from IGDB age rating
                let ratingString = "\(ageRating.category ?? "Unknown")"
                if !seen.contains(ratingString) {
                    result.append(ratingString)
                    seen.insert(ratingString)
                }
            }
        }
        
        return result
    }
}

extension Array where Element == SimpleRomSchema {
    func mapToDomain() -> [Rom] {
        return self.map { RomMapper.mapFromAPI($0) }
    }
}
