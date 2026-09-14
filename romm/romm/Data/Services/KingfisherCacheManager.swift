//
//  KingfisherCacheManager.swift
//  romm
//
//  Created by Ilyas Hallak on 27.08.25.
//

import Foundation
import Kingfisher
import UIKit

// MARK: - Kingfisher Configuration Manager

class KingfisherCacheManager: ObservableObject {
    static let shared = KingfisherCacheManager()
    
    private let settings = ImageCacheSettings.shared

    private var authModifier: AnyModifier?

    /// Cover images are decoded at two sizes so list cells don't evict the memory cache.
    enum CoverImageTier {
        /// List rows and grid cards.
        case thumbnail
        /// Detail hero, screenshots and sheets.
        case full

        /// Downsampling target in points. Both tiers produce their own cache key, which is
        /// intentional: `.cacheOriginalImage` lets the second tier be derived locally instead
        /// of costing another network download.
        var downsampleSize: CGSize {
            switch self {
            case .thumbnail: return CGSize(width: 300, height: 300)
            case .full: return CGSize(width: 600, height: 600)
            }
        }

        /// Short, stable name used to keep the prefetch bookkeeping apart per tier.
        var identifier: String {
            switch self {
            case .thumbnail: return "thumbnail"
            case .full: return "full"
            }
        }
    }

    /// Shared downsampling target so on-demand loads and prefetch produce the same cache key.
    static let downsampleSize = CoverImageTier.full.downsampleSize

    /// Covers are roughly 2 MB each in the thumbnail tier after downsampling, so this budget
    /// keeps several screens worth of grid cells resident instead of re-decoding them on scroll.
    private static let memoryCacheLimitBytes = 180 * 1024 * 1024

    /// Prefetch must not starve the on-demand loads of the cells that are actually on screen.
    private static let maxConcurrentPrefetchDownloads = 4

    /// Image options shared between CachedKFImage and prefetching so both hit the same cache entry.
    static func imageOptions(for tier: CoverImageTier) -> KingfisherOptionsInfo {
        [
            .diskCacheExpiration(.days(30)),
            .backgroundDecode,
            .scaleFactor(UIScreen.main.scale),
            .processor(DownsamplingImageProcessor(size: tier.downsampleSize)),
            .cacheOriginalImage
        ]
    }

    /// Image options shared between CachedKFImage and prefetching so both hit the same cache entry.
    static var sharedImageOptions: KingfisherOptionsInfo {
        imageOptions(for: .full)
    }

    // MARK: - Prefetch State

    /// Guards the prefetch bookkeeping, which is touched from the main actor and from
    /// Kingfisher's completion handlers.
    private let prefetchLock = NSLock()

    /// Cache keys (per tier) that were already requested, so scrolling back and forth does not
    /// start the same prefetch over and over.
    private var requestedPrefetchKeys = Set<String>()

    /// Kingfisher does not retain a prefetcher, so we keep it alive until its completion fires.
    private var activePrefetchers = [UUID: ImagePrefetcher]()

    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        configureKingfisher()
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
    }
    
    func configureKingfisher() {
        // Configure memory cache with reasonable defaults (not user-configurable)
        ImageCache.default.memoryStorage.config.totalCostLimit = Self.memoryCacheLimitBytes
        ImageCache.default.memoryStorage.config.countLimit = 500

        // Configure disk cache with size limit AND expiry
        ImageCache.default.diskStorage.config.sizeLimit = UInt(settings.diskCacheLimitBytes)
        ImageCache.default.diskStorage.config.expiration = .seconds(settings.diskCacheExpirySeconds)

        // Configure downloader
        ImageDownloader.default.downloadTimeout = 30.0
        ImageDownloader.default.sessionConfiguration.httpMaximumConnectionsPerHost = 6

        // Configure default options for KingfisherManager
        KingfisherManager.shared.defaultOptions = [
            .diskCacheExpiration(.seconds(settings.diskCacheExpirySeconds)),
            .backgroundDecode,
            .scaleFactor(UIScreen.main.scale),
            .cacheOriginalImage
        ]

        // updateSettings() runs this again, so the observer has to stay a one-time registration.
        registerMemoryWarningObserverIfNeeded()

        Logger.general.info("🖼️ Kingfisher configured: Memory=\(Self.memoryCacheLimitBytes / 1024 / 1024)MB, Disk=\(settings.diskCacheLimitBytes / 1024 / 1024)MB, Expiry=\(settings.diskCacheExpirySeconds / 86400)d")
    }

    private func registerMemoryWarningObserverIfNeeded() {
        guard memoryWarningObserver == nil else { return }

        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Emulator cores need a lot of RAM, so images are the first thing to give up.
            self?.cancelPrefetching()
            self?.clearMemoryCache()
        }
    }
    
    func updateSettings() {
        configureKingfisher()
        // Let Kingfisher handle cache management automatically
    }
    
    func clearMemoryCache() {
        ImageCache.default.clearMemoryCache()
    }
    
    func clearDiskCache() {
        ImageCache.default.clearDiskCache()
    }
    
    func clearAllCaches() {
        ImageCache.default.clearCache()
    }
    
    func getCacheUsage() -> (memory: Int, disk: Int) {
        // Memory cache: Kingfisher doesn't expose actual memory usage
        // We return 0 since memory cache is transient and not measurable
        let memoryUsed = 0
        
        // For disk cache, we return the last calculated value
        let diskUsed = lastCalculatedDiskSize
        
        return (memory: memoryUsed, disk: diskUsed)
    }
    
    private var lastCalculatedDiskSize: Int = 0
    
    func getCacheUsageAsync(completion: @escaping (Int, Int) -> Void) {
        // Memory cache is transient and not measurable
        let memoryUsed = 0
        
        ImageCache.default.calculateDiskStorageSize { [weak self] result in
            guard let self = self else { return }
            
            let diskUsed = switch result {
            case .success(let size): Int(size)
            case .failure(_): 0
            }
            
            // Store the calculated disk size for sync access
            self.lastCalculatedDiskSize = diskUsed
            
            // Log cache usage but don't force cleanup - let Kingfisher handle it
            let limitBytes = self.settings.diskCacheLimitBytes
            if diskUsed > limitBytes {
                print("ℹ️ Cache usage: \(diskUsed) bytes (limit: \(limitBytes) bytes)")
            }
            
            DispatchQueue.main.async {
                completion(memoryUsed, diskUsed)
            }
        }
    }
    
    // MARK: - Prefetching

    /// Existing call sites prefetch list and grid covers, so they stay on the thumbnail tier.
    func preloadImages(urls: [URL]) {
        prefetch(urls: urls, tier: .thumbnail)
    }

    /// Warms the cache for the given URLs in the given tier.
    ///
    /// URLs that were already requested for the same tier are skipped, and the prefetcher is
    /// retained until its completion handler fires, since Kingfisher does not keep it alive.
    func prefetch(urls: [URL], tier: CoverImageTier) {
        guard settings.preloadEnabled, !urls.isEmpty else { return }

        let pendingURLs = claimPrefetchURLs(urls, tier: tier)
        guard !pendingURLs.isEmpty else { return }

        var options = Self.imageOptions(for: tier)
        if let authModifier {
            options.append(.requestModifier(authModifier))
        }

        let token = UUID()
        let prefetcher = ImagePrefetcher(
            urls: pendingURLs,
            options: options,
            completionHandler: { [weak self] _, failedResources, _ in
                self?.finishPrefetching(token: token, failedResources: failedResources, tier: tier)
            }
        )
        prefetcher.maxConcurrentDownloads = Self.maxConcurrentPrefetchDownloads

        // Retain before starting, the completion handler may fire as soon as start() is called.
        prefetchLock.lock()
        activePrefetchers[token] = prefetcher
        prefetchLock.unlock()

        prefetcher.start()
    }

    /// Stops every running prefetcher and forgets what was requested, so a later scroll can
    /// start over. Used on memory warnings.
    func cancelPrefetching() {
        prefetchLock.lock()
        let running = Array(activePrefetchers.values)
        activePrefetchers.removeAll()
        requestedPrefetchKeys.removeAll()
        prefetchLock.unlock()

        running.forEach { $0.stop() }
    }

    /// Reserves the dedup keys and returns only the URLs that are not requested yet.
    private func claimPrefetchURLs(_ urls: [URL], tier: CoverImageTier) -> [URL] {
        prefetchLock.lock()
        defer { prefetchLock.unlock() }

        return urls.filter { requestedPrefetchKeys.insert(Self.prefetchKey(for: $0.cacheKey, tier: tier)).inserted }
    }

    private func finishPrefetching(token: UUID, failedResources: [any Resource], tier: CoverImageTier) {
        prefetchLock.lock()
        activePrefetchers[token] = nil
        // Failures stay retryable, otherwise a single flaky response hides a cover for good.
        for resource in failedResources {
            requestedPrefetchKeys.remove(Self.prefetchKey(for: resource.cacheKey, tier: tier))
        }
        prefetchLock.unlock()
    }

    private static func prefetchKey(for cacheKey: String, tier: CoverImageTier) -> String {
        "\(tier.identifier)|\(cacheKey)"
    }
    
    // MARK: - Cache Management
    
    private func checkAndCleanCacheIfNeeded() {
        // Only clean expired cache - no aggressive cleanup
        ImageCache.default.cleanExpiredDiskCache()
    }
    
    private func cleanCacheToLimit() {
        // Only clean expired cache - don't be aggressive
        ImageCache.default.cleanExpiredDiskCache()
        
        // Don't clear entire cache - let Kingfisher handle it automatically
        // The size limit in configureKingfisher() will handle automatic cleanup
    }
    
    func forceCacheCleanup() {
        cleanCacheToLimit()
    }

    // MARK: - Auth

    func configureAuth(tokenProvider: PTokenProvider) {
        guard let serverURL = tokenProvider.getServerURL(),
              let serverHost = URL(string: serverURL)?.host else { return }

        let modifier = AnyModifier { request in
            guard request.url?.host == serverHost else { return request }
            var r = request
            let authMethod = tokenProvider.getAuthMethod()
            switch authMethod {
            case .clientToken, .deviceFlow:
                if let token = tokenProvider.getClientToken() {
                    r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            case .classic:
                if let username = tokenProvider.getUsername(),
                   let password = tokenProvider.getPassword(),
                   let data = "\(username):\(password)".data(using: .utf8) {
                    r.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
                }
            }
            return r
        }
        self.authModifier = modifier
        KingfisherManager.shared.defaultOptions += [.requestModifier(modifier)]
    }
}