//
//  PlatformMapper.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

struct PlatformMapper {
    static func mapFromAPI(_ apiPlatform: PlatformSchema) -> Platform {
        // Determine manufacturer from family name or category
        let manufacturer = apiPlatform.familyName ?? apiPlatform.category

        return Platform(
            id: apiPlatform.id,
            name: apiPlatform.name,
            displayName: apiPlatform.displayName,
            slug: apiPlatform.slug,
            igdbId: apiPlatform.igdbId,
            logoPath: apiPlatform.urlLogo,
            romCount: apiPlatform.romCount,
            sizeBytes: apiPlatform.fsSizeBytes,
            manufacturer: manufacturer
        )
    }
}

extension Array where Element == PlatformSchema {
    func mapToDomain() -> [Platform] {
        return self.map { PlatformMapper.mapFromAPI($0) }
    }
}
