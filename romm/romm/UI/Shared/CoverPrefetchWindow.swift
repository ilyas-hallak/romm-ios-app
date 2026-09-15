//
//  CoverPrefetchWindow.swift
//  romm
//
//  Created by Claude on 14.09.26.
//

import Foundation

/// Keeps the covers just below the fold warm while the user scrolls a list.
///
/// A list reports the item whose cell just appeared, and the window prefetches the covers of the
/// items that follow it, so they are decoded before they scroll into view. Deduplication against
/// repeated requests is handled by `KingfisherCacheManager`, this type only makes sure the window
/// is not recalculated for every single cell that appears.
///
/// Usage from a view:
/// ```
/// @State private var prefetchWindow = CoverPrefetchWindow()
/// ...
/// .onAppear { prefetchWindow.update(with: roms) { $0.listCoverURL } }
/// .onChange(of: roms.coverPrefetchToken) { _, _ in prefetchWindow.update(with: roms) { $0.listCoverURL } }
/// ```
@MainActor
final class CoverPrefetchWindow {
    /// How many items ahead of the appearing one are prefetched.
    private let windowSize: Int

    /// The window is only extended again once the appearing index comes this close to its end,
    /// so scrolling a few rows does not rebuild the slice on every `onAppear`.
    private let refillStep: Int

    private let tier: KingfisherCacheManager.CoverImageTier

    /// Cover URLs in the order the list displays them, `nil` for items without a cover.
    private var coverURLs: [URL?] = []
    private var indexByItemID: [AnyHashable: Int] = [:]

    /// Highest index that was already handed to the prefetcher, -1 when nothing was requested yet.
    private var prefetchedUpTo: Int = -1

    init(windowSize: Int = 24, tier: KingfisherCacheManager.CoverImageTier = .thumbnail) {
        self.windowSize = max(1, windowSize)
        self.refillStep = max(1, windowSize / 2)
        self.tier = tier
    }

    /// Replaces the item order the window walks along, for example after a page was appended,
    /// a filter was applied or the sorting changed.
    func update<Item: Identifiable>(with items: [Item], coverURL: (Item) -> String?) {
        coverURLs = items.map { coverURL($0).flatMap(URL.init) }

        var indices: [AnyHashable: Int] = [:]
        indices.reserveCapacity(items.count)
        for (offset, item) in items.enumerated() {
            let key = AnyHashable(item.id)
            // A duplicate id keeps its first position, that is the one the user reaches first.
            if indices[key] == nil {
                indices[key] = offset
            }
        }
        indexByItemID = indices

        prefetchedUpTo = -1

        // The cells report themselves only once they appear, and the order in which SwiftUI runs
        // the `onAppear` of a list and of its cells is not guaranteed. Priming the first window
        // makes sure the top of the list is warm either way, everything already requested is
        // skipped by the cache manager.
        extendWindow(from: -1)
    }

    /// Reports that the cell for the given item id became visible.
    func itemAppeared<ID: Hashable>(id: ID) {
        guard let index = indexByItemID[AnyHashable(id)] else { return }
        extendWindow(from: index)
    }

    /// Drops the current order, used when a list is torn down or reloaded from scratch.
    func reset() {
        coverURLs = []
        indexByItemID = [:]
        prefetchedUpTo = -1
    }

    private func extendWindow(from index: Int) {
        let upperBound = min(index + windowSize, coverURLs.count - 1)

        // Scrolling backwards or standing still, everything ahead is already requested.
        guard upperBound > prefetchedUpTo else { return }

        // Refill in chunks instead of on every appearing cell.
        guard index + refillStep >= prefetchedUpTo else { return }

        let lowerBound = max(prefetchedUpTo + 1, index + 1)
        guard lowerBound <= upperBound else { return }

        prefetchedUpTo = upperBound

        let urls = coverURLs[lowerBound...upperBound].compactMap { $0 }
        guard !urls.isEmpty else { return }

        KingfisherCacheManager.shared.prefetch(urls: urls, tier: tier)
    }
}

// MARK: - Change Detection

extension Array where Element == Rom {
    /// Cheap change token for `onChange`, comparing the whole list on every render would be
    /// far too expensive for a few thousand ROMs.
    var coverPrefetchToken: String {
        "\(count)-\(first?.id ?? -1)-\(last?.id ?? -1)"
    }
}
