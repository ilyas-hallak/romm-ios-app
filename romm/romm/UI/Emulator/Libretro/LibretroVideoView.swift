import UIKit
import CoreGraphics

/// Naive Software-Blit-View: nimmt rohe libretro-Frames entgegen und rendert
/// sie als `CGImage` in ein `CALayer.contents`. Reicht für PCSX ReARMed
/// Bring-Up. Wird später durch eine Metal-Pipeline ersetzt.
final class LibretroVideoView: UIView, LibretroVideoSink {

    override class var layerClass: AnyClass { CALayer.self }

    /// Second layer that receives the same frame, used to paint an external
    /// display (AirPlay or wired). Wired up once and left in place: while no
    /// display is attached the layer sits outside any hierarchy and assigning
    /// `contents` costs next to nothing.
    weak var mirrorLayer: CALayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.magnificationFilter = .nearest
        layer.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func libretroDidProduceFrame(
        data: UnsafeRawPointer?,
        width: UInt32,
        height: UInt32,
        pitch: Int,
        pixelFormat: LibretroABI.PixelFormat
    ) {
        if handleFlashFrame() { return }
        guard let data = data, width > 0, height > 0 else { return }

        let bitmapInfo: CGBitmapInfo
        let bitsPerComponent: Int
        let bitsPerPixel: Int

        switch pixelFormat {
        case .rgb565:
            bitmapInfo = CGBitmapInfo(rawValue:
                CGImagePixelFormatInfo.RGB565.rawValue |
                CGImageByteOrderInfo.order16Little.rawValue |
                CGImageAlphaInfo.none.rawValue
            )
            bitsPerComponent = 5
            bitsPerPixel = 16
        case .xrgb8888:
            bitmapInfo = CGBitmapInfo(rawValue:
                CGImageAlphaInfo.noneSkipFirst.rawValue |
                CGImageByteOrderInfo.order32Little.rawValue
            )
            bitsPerComponent = 8
            bitsPerPixel = 32
        case .rgb1555:
            bitmapInfo = CGBitmapInfo(rawValue:
                CGImagePixelFormatInfo.RGB555.rawValue |
                CGImageByteOrderInfo.order16Little.rawValue |
                CGImageAlphaInfo.noneSkipFirst.rawValue
            )
            bitsPerComponent = 5
            bitsPerPixel = 16
        }

        let bytesTotal = pitch * Int(height)
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: data,
            size: bytesTotal,
            releaseData: { _, _, _ in }
        ) else { return }

        guard let image = CGImage(
            width: Int(width),
            height: Int(height),
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: pitch,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return }

        layer.contents = image
        mirrorLayer?.contents = image
        lastCGImage = image
    }

    private var lastCGImage: CGImage?

    func snapshot() -> UIImage? {
        guard let image = lastCGImage else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - Latency flash test

    /// Measuring aid: replaces a few game frames with pure white on both the
    /// phone and the external display. Because it rides the same layer as the
    /// picture, it goes through the exact same compositing and AirPlay encoding
    /// path, so filming both screens in slow motion and counting the frames
    /// between the two flashes gives the real transport delay.
    ///
    /// Deliberately not a SwiftUI overlay, that would be composited differently
    /// and would measure the wrong thing.
    private var flashFramesRemaining = 0
    private var isFlashing = false
    private var flashTimer: Timer?

    /// White for three frames, roughly 50 ms. A single frame risks being dropped
    /// by the video encoder, while the leading edge stays just as sharp to read.
    private static let flashFrameCount = 3

    func startFlashTest(interval: TimeInterval = 2.0) {
        stopFlashTest()
        flashTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.flashFramesRemaining = Self.flashFrameCount
        }
        print("[Libretro] latency flash test on, every \(interval)s")
    }

    func stopFlashTest() {
        flashTimer?.invalidate()
        flashTimer = nil
        flashFramesRemaining = 0
        if isFlashing { setFlash(false) }
    }

    /// Returns true when this frame was consumed by the flash.
    private func handleFlashFrame() -> Bool {
        if flashFramesRemaining > 0 {
            flashFramesRemaining -= 1
            if !isFlashing { setFlash(true) }
            return true
        }
        if isFlashing { setFlash(false) }
        return false
    }

    private func setFlash(_ on: Bool) {
        isFlashing = on
        let color = (on ? UIColor.white : UIColor.black).cgColor
        // Dropping `contents` is what makes the layer show its background, and it
        // avoids allocating a white image per flash.
        if on { layer.contents = nil; mirrorLayer?.contents = nil }
        layer.backgroundColor = color
        mirrorLayer?.backgroundColor = color
    }
}
