import Testing
import SwiftUI
import UIKit
import Kingfisher
@testable import romm

// Regression test for a bug where a landscape cover widened `BigRomCardView` past its
// grid column. `Image.resizable().aspectRatio(contentMode: .fill)` reports the size it
// scaled to, and a `.frame(maxWidth: .infinity)` never shrinks below its child, so a
// 320x240 cover at 180pt height used to report 240pt width even though the grid column
// is only ~170pt wide. The fix sizes a `Color.clear` frame and paints the cover as an
// `.overlay`, which no longer feeds its size back into the layout.
//
// This test measures the real `BigRomCardView`, not a stand-in, by seeding Kingfisher's
// memory cache directly so the view renders the actual cover instead of its placeholder.
@MainActor
struct BigRomCardLayoutTests {

    /// Width of a grid column on a regular iPhone, the card must not report more than this.
    private let columnWidth: CGFloat = 170

    private func makeImage(width: CGFloat, height: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// `CachedKFImage.loadImage()` looks up `.thumbnail` tier options at `.visible` priority,
    /// so storing under anything else would land on a different processor identifier and the
    /// view would silently render its placeholder instead of this image.
    private func thumbnailOptions() -> KingfisherParsedOptionsInfo {
        KingfisherParsedOptionsInfo(
            KingfisherCacheManager.imageOptions(for: .thumbnail, priority: .visible)
        )
    }

    private func cacheImage(_ image: UIImage, for url: URL) {
        let options = thumbnailOptions()
        ImageCache.default.store(image, forKey: url.cacheKey, options: options, toDisk: false)

        // Guard against a silent measurement of the placeholder if the key ever drifts
        // out of sync with what CachedKFImage looks up.
        let cached = ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey, options: options)
        #expect(cached != nil)
    }

    private func removeCachedImage(for url: URL) {
        // Kingfisher keys memory entries by cacheKey plus processor identifier, and its
        // removal API takes that identifier directly rather than a whole options bag.
        ImageCache.default.removeImage(
            forKey: url.cacheKey,
            processorIdentifier: thumbnailOptions().processor.identifier,
            fromMemory: true,
            fromDisk: false
        )
    }

    private func makeRom(coverURLString: String) -> Rom {
        Rom(
            id: 1,
            name: "Test Game",
            platformId: 6,
            coverURLSmall: coverURLString
        )
    }

    /// Width the card reports for a grid column of `columnWidth`.
    ///
    /// The card is hosted in a real window and laid out first: `CachedKFImage` only loads in
    /// `onAppear`, which never runs for a detached `sizeThatFits` call. Measuring without this
    /// would size the size-neutral placeholder and pass no matter what the cover looks like.
    private func measuredWidth(for rom: Rom) -> CGFloat {
        let host = UIHostingController(rootView: BigRomCardView(rom: rom))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: columnWidth, height: 2000))
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()

        // Let the onAppear hop through the run loop so the cached cover reaches the view state.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.view.layoutIfNeeded()

        let fitted = host.sizeThatFits(in: CGSize(width: columnWidth, height: 2000))
        window.isHidden = true
        window.rootViewController = nil
        return fitted.width
    }

    @Test func landscapeCoverDoesNotWidenTheCard() throws {
        let url = try #require(URL(string: "https://romm.example.com/test-cover-landscape.png"))
        cacheImage(makeImage(width: 320, height: 240), for: url)
        defer { removeCachedImage(for: url) }

        // Before the fix this measured the width the 4:3 cover scaled to at 180pt height.
        let width = measuredWidth(for: makeRom(coverURLString: url.absoluteString))
        #expect(width <= columnWidth)
    }

    @Test func portraitCoverStillFitsTheCard() throws {
        // Control case: portrait covers already fit before the fix, so this proves the
        // fix does not just clamp everything to the column width regardless of the image.
        let url = try #require(URL(string: "https://romm.example.com/test-cover-portrait.png"))
        cacheImage(makeImage(width: 240, height: 360), for: url)
        defer { removeCachedImage(for: url) }

        let width = measuredWidth(for: makeRom(coverURLString: url.absoluteString))
        #expect(width <= columnWidth)
    }
}
