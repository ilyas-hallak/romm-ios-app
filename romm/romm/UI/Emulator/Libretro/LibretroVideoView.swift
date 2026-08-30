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
        case .rgba8888:
            // Bytes liegen in Speicherreihenfolge R,G,B,A vor (so liefert
            // glReadPixels GL_RGBA/GL_UNSIGNED_BYTE). Damit CoreGraphics genau
            // diese Reihenfolge liest: byteOrder32Big (Byte 0 = hoechstwertig,
            // also erste Komponente) + Alpha last. Das ergibt R,G,B,A ab Byte 0
            // und stellt den roten Testpuffer korrekt dar. Verifiziert am
            // roten-Bildschirm-Test (Meilenstein 1): jede andere Kombination
            // (order32Little / alpha first) kippt Rot nach Blau bzw. verschiebt
            // die Kanaele.
            bitmapInfo = CGBitmapInfo(rawValue:
                CGImageByteOrderInfo.order32Big.rawValue |
                CGImageAlphaInfo.premultipliedLast.rawValue
            )
            bitsPerComponent = 8
            bitsPerPixel = 32
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
}
