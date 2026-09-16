import Testing
import Foundation
import UIKit
@testable import romm

/// The external picture surface. What is tested here is not pixels but Core
/// Animation's implicit behaviour, which is what made the TV picture trail
/// behind the phone: a layer that does not back a view animates every
/// `contents` assignment over a quarter of a second unless it says otherwise.
@MainActor
struct ExternalDisplayContentViewTests {

    /// Spelled out rather than read from `unanimatedKeys`, so the test fails if
    /// a key is dropped from that list.
    @Test(arguments: ["contents", "contentsRect", "contentsScale", "bounds", "position"])
    func videoLayerRefusesImplicitAnimations(key: String) {
        let view = ExternalDisplayContentView()
        #expect(view.videoLayer.actions?.keys.contains(key) == true)
        // The `NSNull` placeholder reaches Swift as `nil`, and nothing to run is
        // what Core Animation reads as "leave this property alone".
        #expect(view.videoLayer.action(forKey: key) == nil)
    }

    /// The layer has no delegate to fall back on, which is exactly why the
    /// actions have to be declared on it.
    @Test func videoLayerHasNoDelegateToSuppressAnimationsForIt() {
        let view = ExternalDisplayContentView()
        #expect(view.videoLayer.delegate == nil)
    }

    /// A frame assigned outside an animation block must appear at once. Asked
    /// through `action(forKey:)` because that is what Core Animation itself
    /// consults; `animationKeys()` stays nil in a test either way and would
    /// pass with the suppression removed.
    @Test func assigningContentsFindsNoActionToRun() {
        let view = ExternalDisplayContentView()
        view.videoLayer.contents = UIImage(systemName: "tv")?.cgImage
        #expect(view.videoLayer.action(forKey: "contents") == nil)
    }

    /// A standalone layer starts at scale 1 and inherits nothing, so the screen
    /// it ends up on has to be read off the window.
    @Test func videoLayerTakesTheScaleOfTheScreenItLandsOn() {
        let view = ExternalDisplayContentView()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        window.addSubview(view)
        #expect(view.videoLayer.contentsScale == window.screen.scale)
    }

    /// Filling the surface is the whole job: a layer left at zero size shows
    /// black however many frames arrive.
    @Test func videoLayerFillsTheSurfaceAfterLayout() {
        let view = ExternalDisplayContentView()
        view.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        view.layoutIfNeeded()
        #expect(view.videoLayer.frame == view.bounds)
        #expect(view.videoLayer.action(forKey: "bounds") == nil)
    }
}

/// The per-frame side of the same problem: the view paints its own layer and a
/// mirror layer, and only the first one is protected by belonging to a view.
@MainActor
struct LibretroVideoViewMirroringTests {

    /// Two by two in RGB565. Deliberately never freed: `CGDataProvider` keeps
    /// the pointer without copying, and the image outlives this call.
    private func makeFrame() -> UnsafeMutableRawPointer {
        let pixels: [UInt16] = [0xF800, 0x07E0, 0x001F, 0xFFFF]
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 2)
        pixels.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: 8) }
        return buffer
    }

    private func sendFrame(to view: LibretroVideoView) {
        view.libretroDidProduceFrame(
            data: UnsafeRawPointer(makeFrame()),
            width: 2, height: 2, pitch: 4, pixelFormat: .rgb565
        )
    }

    @Test func theMirrorLayerGetsTheSameFrame() {
        let view = LibretroVideoView(frame: .zero)
        let mirror = CALayer()
        view.mirrorLayer = mirror
        sendFrame(to: view)
        #expect(mirror.contents != nil)
    }

    /// Stands in for whatever Core Animation would do to a `contents`
    /// assignment, since the crossfade itself cannot be observed from a test.
    private final class ActionSpy: NSObject, CAAction {
        var runCount = 0
        func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
            runCount += 1
        }
    }

    /// The regression this whole change is about: at 60 frames a second an
    /// implicit crossfade per assignment leaves a permanently dissolving picture
    /// on the TV. A layer handed in from elsewhere may well have an action for
    /// `contents`, and the assignment has to step around it.
    @Test func theMirrorLayerIsNeverAnimatedIntoTheNextFrame() {
        let view = LibretroVideoView(frame: .zero)
        let mirror = CALayer()
        let spy = ActionSpy()
        mirror.actions = ["contents": spy]
        view.mirrorLayer = mirror
        sendFrame(to: view)
        sendFrame(to: view)
        #expect(spy.runCount == 0)
    }

    /// Guards the test above from passing for the wrong reason: the same layer
    /// does run its action when the assignment is made the ordinary way.
    @Test func theSpyWouldNoticeAnUnguardedAssignment() {
        let mirror = CALayer()
        let spy = ActionSpy()
        mirror.actions = ["contents": spy]
        mirror.contents = UIImage(systemName: "tv")?.cgImage
        #expect(spy.runCount == 1)
    }

    @Test func withoutAMirrorLayerTheViewStillPaintsItself() {
        let view = LibretroVideoView(frame: .zero)
        sendFrame(to: view)
        #expect(view.layer.contents != nil)
        #expect(view.snapshot() != nil)
    }

    /// The frame rate is only as good as the seam it is counted in, so every
    /// frame that reaches the mirror has to be reported.
    @Test func everyMirroredFrameIsReported() {
        let view = LibretroVideoView(frame: .zero)
        let diagnostics = DiagnosticsSpy()
        // Held here on purpose: the view keeps the mirror weakly, so a layer
        // nobody else owns is gone before the first frame arrives.
        let mirror = CALayer()
        view.diagnostics = diagnostics
        view.mirrorLayer = mirror
        sendFrame(to: view)
        sendFrame(to: view)
        sendFrame(to: view)
        #expect(diagnostics.frameCount == 3)
        #expect(mirror.contents != nil)
    }

    /// Nothing of ours is on a display, so counting would report a rate for a
    /// picture nobody is watching.
    @Test func framesAreNotReportedWithoutAMirrorLayer() {
        let view = LibretroVideoView(frame: .zero)
        let diagnostics = DiagnosticsSpy()
        view.diagnostics = diagnostics
        sendFrame(to: view)
        #expect(diagnostics.frameCount == 0)
    }
}

@MainActor
final class DiagnosticsSpy: PExternalDisplayDiagnostics {
    private(set) var frameCount = 0
    private(set) var renderingStarts: [Bool] = []

    func sessionDidBegin() {}
    func sessionDidEnd() {}
    func displayDidConnect(_ display: ExternalDisplayMetrics) {}
    func displayDidDisconnect() {}
    func renderingDidStart(on display: ExternalDisplayMetrics, countingFrames: Bool) {
        renderingStarts.append(countingFrames)
    }
    func renderingDidStop() {}
    func externalFrameRendered() { frameCount += 1 }
}

struct ExternalFrameRateCounterTests {

    /// A rate needs two points in time, so the first frame can only open a
    /// window.
    @Test func theFirstFrameReportsNothing() {
        var counter = ExternalFrameRateCounter()
        #expect(counter.record(at: 0) == nil)
    }

    @Test func staysSilentInsideAnOpenWindow() {
        var counter = ExternalFrameRateCounter()
        _ = counter.record(at: 0)
        #expect(counter.record(at: 0.5) == nil)
        #expect(counter.record(at: 0.9) == nil)
    }

    /// Sixty frames spread over a second have to read as sixty a second, not as
    /// the fifty nine that dropping the window opener would produce.
    @Test func reportsTheRateOfTheWindowThatJustClosed() throws {
        var counter = ExternalFrameRateCounter()
        _ = counter.record(at: 0)
        var reported: Double?
        for frame in 1...60 {
            reported = counter.record(at: Double(frame) / 60)
        }
        let rate = try #require(reported)
        #expect(abs(rate - 60) < 0.001)
    }

    /// The next window starts at the frame that closed the previous one, so a
    /// steady stream keeps reporting the same rate instead of drifting.
    @Test func windowsFollowEachOtherWithoutAGap() {
        var counter = ExternalFrameRateCounter()
        _ = counter.record(at: 0)
        var rates: [Double] = []
        for frame in 1...120 {
            if let rate = counter.record(at: Double(frame) / 60) { rates.append(rate) }
        }
        #expect(rates.count == 2)
        #expect(rates.allSatisfy { abs($0 - 60) < 0.001 })
    }

    /// After a pause the open window covers time in which nothing was painted,
    /// and reporting that as a frame rate would invent a stall.
    @Test func resetDropsTheOpenWindow() {
        var counter = ExternalFrameRateCounter()
        _ = counter.record(at: 0)
        _ = counter.record(at: 0.5)
        counter.reset()
        #expect(counter.record(at: 10) == nil)
        #expect(counter.record(at: 10.5) == nil)
    }

    /// Nobody calls `reset()` for the in-game menu, so a gap between two frames
    /// has to speak for itself. Thirty seconds in a menu must not come back as
    /// a fraction of a frame a second on the frame that follows it.
    @Test func aGapBetweenFramesCountsAsAPauseRatherThanAStall() {
        var counter = ExternalFrameRateCounter()
        _ = counter.record(at: 0)
        _ = counter.record(at: 0.5)
        #expect(counter.record(at: 30) == nil)
        #expect(counter.record(at: 30.5) == nil)
    }

    /// A picture limping along at one frame a second is exactly the collapse
    /// this is meant to catch, so the pause threshold must not swallow it.
    @Test func aSlowButSteadyRateIsStillReported() throws {
        var counter = ExternalFrameRateCounter()
        _ = counter.record(at: 0)
        let reported = counter.record(at: 1)
        let rate = try #require(reported)
        #expect(abs(rate - 1) < 0.001)
    }

    /// A late frame is not a pause: the window it lands in still has to close.
    @Test func aSingleLateFrameStillClosesItsWindow() throws {
        var counter = ExternalFrameRateCounter()
        _ = counter.record(at: 0)
        _ = counter.record(at: 0.4)
        _ = counter.record(at: 0.8)
        let reported = counter.record(at: 1.2)
        let rate = try #require(reported)
        #expect(abs(rate - 2.5) < 0.001)
    }
}
