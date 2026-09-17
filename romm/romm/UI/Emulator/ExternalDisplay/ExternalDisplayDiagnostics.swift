import AVFoundation
import UIKit

/// Reports what the app does to an external display, so the delay on a TV
/// (issue #147) can be measured rather than guessed at.
@MainActor
protocol PExternalDisplayDiagnostics: AnyObject {
    func sessionDidBegin()
    func sessionDidEnd()
    func displayDidConnect(_ display: ExternalDisplayMetrics)
    func displayDidDisconnect()
    func renderingDidStart(on display: ExternalDisplayMetrics, countingFrames: Bool)
    func renderingDidStop()
    func externalFrameRendered()
}

/// All the diagnostics needs to know about an external screen. A plain value so
/// none of this depends on holding a live UIKit scene.
struct ExternalDisplayMetrics: Equatable {
    let pointSize: CGSize
    let pixelSize: CGSize
    let scale: CGFloat
    let maximumFramesPerSecond: Int

    init(screen: UIScreen) {
        self.init(
            pointSize: screen.bounds.size,
            pixelSize: screen.nativeBounds.size,
            scale: screen.scale,
            maximumFramesPerSecond: screen.maximumFramesPerSecond
        )
    }

    init(pointSize: CGSize, pixelSize: CGSize, scale: CGFloat, maximumFramesPerSecond: Int) {
        self.pointSize = pointSize
        self.pixelSize = pixelSize
        self.scale = scale
        self.maximumFramesPerSecond = maximumFramesPerSecond
    }
}

/// Puts numbers on the three things that were invisible before: the display we
/// paint and at what size, what the audio route costs, and whether the second
/// output path costs frames.
///
/// Uses `Logger.performance` rather than `os_signpost` because the setup under
/// test is a phone on a TV in a living room: that channel already has a switch
/// in Settings and is readable without a tethered Mac.
@MainActor
final class ExternalDisplayDiagnostics: PExternalDisplayDiagnostics {

    private var frameRate = ExternalFrameRateCounter()
    private var routeObserver: NSObjectProtocol?

    /// Formatted for the log line, so the frame rate can name its output.
    private var renderedSizeDescription: String?

    // MARK: - Session lifecycle

    /// Watched for the whole session, not just while a display is attached:
    /// AirPlay can move the audio before any display scene arrives, and that
    /// move is when the output latency jumps.
    func sessionDidBegin() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            // Route notifications arrive on an internal queue, the logging state
            // lives on the main actor.
            Task { @MainActor in Self.logAudioRoute("audio route changed") }
        }
        Self.logAudioRoute("session started")
    }

    func sessionDidEnd() {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        frameRate.reset()
        renderedSizeDescription = nil
    }

    // MARK: - Display lifecycle

    func displayDidConnect(_ display: ExternalDisplayMetrics) {
        Logger.performance.info(String(
            format: "external display connected: %.0fx%.0f pt at %.1fx (%.0fx%.0f px), up to %ld Hz",
            display.pointSize.width, display.pointSize.height, display.scale,
            display.pixelSize.width, display.pixelSize.height,
            display.maximumFramesPerSecond
        ))
        // Over AirPlay the audio usually moved a moment earlier, so compare this
        // against the reading from `sessionDidBegin`.
        Self.logAudioRoute("with the display attached")
    }

    func displayDidDisconnect() {
        Logger.performance.info("external display disconnected")
        Self.logAudioRoute("after the display went away")
    }

    /// The app now owns the display, which is what makes the rate below
    /// meaningful: plain mirroring produces no frames of ours at all.
    ///
    /// Ignored while already rendering, so the repeated `sync()` calls behind a
    /// single takeover report it once.
    /// - Parameter countingFrames: Whether the renderer reports its frames. Said
    ///   out loud because silence afterwards otherwise reads as a rate of zero.
    func renderingDidStart(on display: ExternalDisplayMetrics, countingFrames: Bool) {
        guard renderedSizeDescription == nil else { return }
        let size = String(
            format: "%.0fx%.0f at %.1fx",
            display.pointSize.width, display.pointSize.height, display.scale
        )
        renderedSizeDescription = size
        frameRate.reset()
        Logger.performance.info(String(
            format: "painting the external display ourselves, %@%@",
            size,
            countingFrames ? "" : ", frames not counted on this path"
        ))
    }

    func renderingDidStop() {
        guard renderedSizeDescription != nil else { return }
        renderedSizeDescription = nil
        frameRate.reset()
        Logger.performance.info("external display released back to mirroring")
    }

    // MARK: - Frames

    /// Called once per frame that reached the external surface. Whether the
    /// second output path costs frames is only visible next to the phone's own
    /// rate, which `LibretroFrontend` already reports.
    func externalFrameRendered() {
        // Runs per frame, so it buys its way out before doing anything while
        // nobody is reading. The gap that leaves resets the window by itself.
        guard LogConfiguration.shared.showPerformanceLogs else { return }
        guard let rate = frameRate.record(at: CACurrentMediaTime()) else { return }
        Logger.performance.debug(String(
            format: "external video: %.2f frames/s to %@, audio out latency %.1f ms",
            rate,
            renderedSizeDescription ?? "the external display",
            AVAudioSession.sharedInstance().outputLatency * 1000
        ))
    }

    // MARK: - Helpers

    private static func logAudioRoute(_ occasion: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ", ")
        // `outputLatency` covers the way from the app's mixer to the speaker,
        // AirPlay hop included, so a value in the hundreds of milliseconds is not
        // ours to fix in the renderer.
        Logger.performance.info(String(
            format: "%@: output %@, out latency %.1f ms, io buffer %.1f ms, %.0f Hz, category %@",
            occasion,
            outputs.isEmpty ? "none" : outputs,
            session.outputLatency * 1000,
            session.ioBufferDuration * 1000,
            session.sampleRate,
            session.category.rawValue
        ))
    }
}

/// Counts frames into windows of roughly a second and reports the rate of each
/// window as it closes.
///
/// Its own type so the arithmetic can be tested without a display.
struct ExternalFrameRateCounter {

    /// Shorter windows make a single late frame look like a rate collapse.
    static let windowSeconds: CFTimeInterval = 1

    /// A gap longer than this is the game standing still, not a slow frame: the
    /// in-game menu, a pause, the app in the background.
    ///
    /// Generous on purpose. The threshold is also the slowest rate that can
    /// still be reported, and a picture limping along at one frame a second is
    /// exactly what this is meant to catch, so it must not be mistaken for a
    /// pause. Menus last longer than this anyway.
    static let pauseSeconds: CFTimeInterval = 2

    private var windowStart: CFTimeInterval?
    private var lastFrame: CFTimeInterval?
    private var framesInWindow = 0

    /// - Returns: The frame rate of the window that just closed, or `nil` while
    ///   the current one is still open. The first call only opens a window: a
    ///   rate needs two points in time.
    mutating func record(at now: CFTimeInterval) -> Double? {
        if let lastFrame, now - lastFrame > Self.pauseSeconds {
            reset()
        }
        lastFrame = now
        guard let start = windowStart else {
            windowStart = now
            framesInWindow = 0
            return nil
        }
        framesInWindow += 1
        let elapsed = now - start
        guard elapsed >= Self.windowSeconds else { return nil }
        let rate = Double(framesInWindow) / elapsed
        windowStart = now
        framesInWindow = 0
        return rate
    }

    /// Drops the open window, so the first rate after a pause or a reconnect is
    /// not diluted by the time the display was not being painted.
    mutating func reset() {
        windowStart = nil
        lastFrame = nil
        framesInWindow = 0
    }
}
