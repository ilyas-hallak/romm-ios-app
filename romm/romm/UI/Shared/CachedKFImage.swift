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
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        CachedKFImageLoader(
            url: url,
            content: content,
            placeholder: placeholder
        )
    }
}

// MARK: - Internal Image Loader using KFImage

private struct CachedKFImageLoader<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: KFCrossPlatformImage?

    var body: some View {
        Group {
            if let loadedImage = loadedImage {
                content(Image(uiImage: loadedImage))
            } else {
                placeholder()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            loadedImage = nil
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = url else { return }

        let options = KingfisherCacheManager.sharedImageOptions

        // Return a cached image synchronously to avoid the placeholder flashing while scrolling.
        if let cached = ImageCache.default.retrieveImageInMemoryCache(
            forKey: url.cacheKey,
            options: KingfisherParsedOptionsInfo(options)
        ) {
            loadedImage = cached
            return
        }

        KingfisherManager.shared.retrieveImage(with: url, options: options) { result in
            switch result {
            case .success(let value):
                loadedImage = value.image

            case .failure(let error):
                Logger.general.error("❌ Failed to load image from \(url): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Convenience Initializers

extension CachedKFImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.init(
            url: url,
            content: { $0 },
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

extension CachedKFImage where Placeholder == Color {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            url: url,
            content: content,
            placeholder: { Color.gray.opacity(0.3) }
        )
    }
}

// MARK: - String URL Convenience

extension CachedKFImage {
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        let url = urlString.flatMap(URL.init)
        self.init(url: url, content: content, placeholder: placeholder)
    }
}

extension CachedKFImage where Content == Image, Placeholder == Color {
    init(urlString: String?) {
        let url = urlString.flatMap(URL.init)
        self.init(url: url)
    }
}
