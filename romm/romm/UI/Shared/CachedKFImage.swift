//
//  CachedKFImage.swift
//  romm
//
//  Created by Claude on 15.11.25.
//

import SwiftUI
import Kingfisher

// MARK: - Cached Image using KFImage (Native Kingfisher SwiftUI Support)

struct CachedKFImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let tier: KingfisherCacheManager.CoverImageTier
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    init(
        url: URL?,
        tier: KingfisherCacheManager.CoverImageTier = .thumbnail,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.tier = tier
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        CachedKFImageLoader(
            url: url,
            tier: tier,
            content: content,
            placeholder: placeholder
        )
    }
}

// MARK: - Internal Image Loader using KFImage

private struct CachedKFImageLoader<Content: View, Placeholder: View>: View {
    let url: URL?
    let tier: KingfisherCacheManager.CoverImageTier
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: KFCrossPlatformImage?
    /// URL that `loadedImage` belongs to, so a recycled cell never shows the previous cover.
    @State private var loadedURL: URL?
    /// URL of the request that is currently in flight.
    @State private var requestedURL: URL?

    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                content(Image(uiImage: loadedImage))
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            loadedImage = nil
            loadedURL = nil
            requestedURL = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = url else { return }

        // onAppear fires again on every cell reuse, don't reload what is already on screen.
        if loadedImage != nil, loadedURL == url { return }

        let options = KingfisherCacheManager.imageOptions(for: tier)

        // Return a cached image synchronously to avoid the placeholder flashing while scrolling.
        if let cached = ImageCache.default.retrieveImageInMemoryCache(
            forKey: url.cacheKey,
            options: KingfisherParsedOptionsInfo(options)
        ) {
            // No animation here, the image was there before the cell was drawn.
            loadedImage = cached
            loadedURL = url
            requestedURL = url
            return
        }

        requestedURL = url

        // Running requests are deliberately not cancelled on disappear, fast scrolling should
        // keep the downloads it already started.
        KingfisherManager.shared.retrieveImage(with: url, options: options) { result in
            // Kingfisher calls back on the main queue, but the closure itself is Sendable,
            // so the isolation has to be stated for the state mutations below.
            MainActor.assumeIsolated {
                // A late result must not land in a cell that has been recycled to another URL.
                guard requestedURL == url else { return }

                switch result {
                case .success(let value):
                    loadedURL = url
                    withAnimation(.easeOut(duration: 0.2)) {
                        loadedImage = value.image
                    }

                case .failure(let error):
                    Logger.general.error("❌ Failed to load image from \(url): \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Convenience Initializers

extension CachedKFImage where Content == Image, Placeholder == Color {
    init(url: URL?, tier: KingfisherCacheManager.CoverImageTier = .thumbnail) {
        self.init(
            url: url,
            tier: tier,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension CachedKFImage where Placeholder == Color {
    init(
        url: URL?,
        tier: KingfisherCacheManager.CoverImageTier = .thumbnail,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            tier: tier,
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

// MARK: - String URL Convenience

extension CachedKFImage {
    init(
        urlString: String?,
        tier: KingfisherCacheManager.CoverImageTier = .thumbnail,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        let url = urlString.flatMap(URL.init)
        self.init(url: url, tier: tier, content: content, placeholder: placeholder)
    }
}

extension CachedKFImage where Content == Image, Placeholder == Color {
    init(urlString: String?, tier: KingfisherCacheManager.CoverImageTier = .thumbnail) {
        let url = urlString.flatMap(URL.init)
        self.init(url: url, tier: tier)
    }
}
