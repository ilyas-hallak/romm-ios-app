import UIKit

/// Sends libretro's picture to an external display.
///
/// Cheap by construction: the video view already builds one `CGImage` per frame
/// for the phone, so the TV costs a second `contents` assignment of an image that
/// exists either way.
@MainActor
final class LibretroExternalRenderTarget: PExternalRenderTarget {

    private weak var videoView: LibretroVideoView?

    init(videoView: LibretroVideoView) {
        self.videoView = videoView
    }

    func startRendering(into surface: PExternalDisplaySurface) {
        videoView?.mirrorLayer = surface.videoLayer
    }

    func stopRendering() {
        videoView?.mirrorLayer = nil
    }
}
