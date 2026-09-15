//
//  CoverPrefetchWindow.swift
//  romm
//
//  Created by Claude on 14.09.26.
//

import Foundation

/// Keeps the covers just below the fold warm while the user scrolls a list.
///
/// A list reports the item whose cell just appeared, and the window prefetches the covers around
/// it, so they are decoded before they scroll into view. The window follows the current position
/// instead of tracking a high-water mark, otherwise jumping backwards, for example through the
/// letter index, would leave everything below the furthest reached row unloaded forever.
/// Deduplication against repeated requests is handled by `KingfisherCacheManager`, this type only
/// makes sure the window is not recalculated for every single cell that appears.
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
    /// How many items ahead of the appearing one are prefetched. Covers are downsampled to the
    /// thumbnail tier and therefore roughly five times smaller than before, so a window of 48
    /// costs about 16 MB and also covers fast scrolling through a grid.
    private let windowSize: Int

    /// The window is only rebuilt once the appearing index moved this far away from the last
    /// refill, so scrolling a few rows does not rebuild the slice on every `onAppear`.
    private let refillStep: Int

    private let tier: KingfisherCacheManager.CoverImageTier

    /// Hands the collected URLs to the image pipeline, injectable so tests do not hit the network.
    private let prefetch: ([URL], KingfisherCacheManager.CoverImageTier) -> Void

    /// Cover URLs in the order the list displays them, `nil` for items without a cover.
    private var coverURLs: [URL?] = []
    private var indexByItemID: [AnyHashable: Int] = [:]

    /// Index the last window was built around, `Int.min` when nothing was requested yet.
    private var lastRefillIndex: Int = .min

    init(windowSize: Int = 48,
         tier: KingfisherCacheManager.CoverImageTier = .thumbnail,
         prefetch: @escaping ([URL], KingfisherCacheManager.CoverImageTier) -> Void = { KingfisherCacheManager.shared.prefetch(urls: $0, tier: $1) }) {
        self.windowSize = max(1, windowSize)
        self.refillStep = max(1, windowSize / 2)
        self.tier = tier
        self.prefetch = prefetch
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

        lastRefillIndex = .min

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
        lastRefillIndex = .min
    }

    private func extendWindow(from index: Int) {
        // Refill in chunks instead of on every appearing cell, in either scroll direction.
        // The `.min` case is spelled out because the subtraction below would overflow on it.
        if lastRefillIndex != .min {
            guard abs(index - lastRefillIndex) >= refillStep else { return }
        }

        lastRefillIndex = index

        let lowerBound = max(0, index - refillStep)
        let upperBound = min(index + windowSize, coverURLs.count - 1)
        guard lowerBound <= upperBound else { return }

        // The small backwards margin helps after a jump and costs nothing, the cache manager
        // already skips keys it requested before.
        let urls = coverURLs[lowerBound...upperBound].compactMap { $0 }
        guard !urls.isEmpty else { return }

        prefetch(urls, tier)
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
