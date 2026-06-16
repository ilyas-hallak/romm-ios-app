//
//  CollectionMapper.swift
//  romm
//
//  Created by Ilyas Hallak on 10.08.25.
//

import Foundation

extension DateFormatter {
    static let iso8601Full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

struct CollectionMapper {
    static func mapFromAPI(_ apiCollection: CollectionSchema) -> Collection {
        return Collection(
            id: apiCollection.id,
            name: apiCollection.name,
            description: apiCollection.description ?? "",
            romIds: apiCollection.romIds,
            romCount: apiCollection.romCount,
            urlCover: apiCollection.urlCover,
            pathCoversSmall: apiCollection.pathCoversSmall,
            userId: apiCollection.userId,
            userUsername: apiCollection.userUsername,
            isPublic: apiCollection.isPublic ?? false,
            isFavorite: apiCollection.isFavorite ?? false,
            isVirtual: apiCollection.isVirtual ?? false,
            isSmart: apiCollection.isSmart ?? false,
            createdAt: DateFormatter.iso8601Full.string(from: apiCollection.createdAt),
            updatedAt: DateFormatter.iso8601Full.string(from: apiCollection.updatedAt)
        )
    }
    
    static func mapVirtualFromAPI(_ apiCollection: VirtualCollectionSchema) -> VirtualCollection {
        return VirtualCollection(
            id: apiCollection.id,
            name: apiCollection.name,
            description: apiCollection.description,
            romIds: apiCollection.romIds,
            romCount: apiCollection.romCount,
            urlCover: apiCollection.pathCoverLarge ?? apiCollection.pathCoverSmall,
            type: apiCollection.type,
            isPublic: apiCollection.isPublic ?? true,
            isFavorite: apiCollection.isFavorite ?? false,
            isVirtual: apiCollection.isVirtual ?? true,
            createdAt: DateFormatter.iso8601Full.string(from: apiCollection.createdAt),
            updatedAt: DateFormatter.iso8601Full.string(from: apiCollection.updatedAt)
        )
    }
}

extension Array where Element == CollectionSchema {
    func mapToDomain() -> [Collection] {
        return self.map { CollectionMapper.mapFromAPI($0) }
    }
}

extension Array where Element == VirtualCollectionSchema {
    func mapVirtualToDomain() -> [VirtualCollection] {
        return self.map { CollectionMapper.mapVirtualFromAPI($0) }
    }
}