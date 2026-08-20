//
//  FavouritesStore.swift
//  romm
//

import Foundation
import Observation

/// App-wide cache of favourite ROM IDs, loaded once from the server and kept in
/// sync when the user toggles a favourite. Views read this directly so that the
/// heart badge in list cards reflects the real server state without every list
/// view having to manage its own favourites fetch.
///
/// Usage pattern mirrors DownloadQueueManager: share as `.shared`, observe in
/// SwiftUI views, mutate via `setFavourite(_:isFavourite:)`.
@Observable
@MainActor
final class FavouritesStore {
    static let shared = FavouritesStore()

    /// IDs of all ROMs that are in the Favourites collection.
    private(set) var favouriteIds: Set<Int> = []

    /// True while the initial fetch is in progress.
    private(set) var isLoading: Bool = false

    private var hasFetched: Bool = false

    private let apiClient: PRommAPIClient
    private let logger = Logger.data

    init(apiClient: PRommAPIClient = RommAPIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - Public API

    /// Returns whether a given ROM is marked as favourite according to the cached set.
    func isFavourite(romId: Int) -> Bool {
        favouriteIds.contains(romId)
    }

    /// Fetches the Favourites collection from the server and refreshes the cache.
    /// Safe to call multiple times: subsequent calls while a fetch is in progress
    /// are no-ops, and a force refresh skips the guard.
    func refresh(force: Bool = false) async {
        guard !isLoading else { return }
        guard force || !hasFetched else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let collections = try await apiClient.getCollections(limit: nil, offset: nil)
            if let favouritesCollection = collections.first(where: { $0.isFavorite == true }) {
                favouriteIds = favouritesCollection.romIds
                logger.info("FavouritesStore: loaded \(favouriteIds.count) favourite ROM IDs from collection \(favouritesCollection.id)")
            } else {
                favouriteIds = []
                logger.info("FavouritesStore: no Favourites collection found on server")
            }
            hasFetched = true
        } catch {
            logger.error("FavouritesStore: failed to load favourites - \(error)")
        }
    }

    /// Optimistically updates the local cache after the user toggles a favourite.
    /// Call this after a successful `toggleRomFavorite` API call so the badge
    /// updates instantly without waiting for a full refresh.
    func setFavourite(_ romId: Int, isFavourite: Bool) {
        if isFavourite {
            favouriteIds.insert(romId)
        } else {
            favouriteIds.remove(romId)
        }
    }
}
