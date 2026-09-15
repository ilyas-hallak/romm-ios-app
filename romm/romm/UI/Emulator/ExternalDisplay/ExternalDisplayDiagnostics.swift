import AVFoundation
import UIKit

/// Puts numbers on what the app does to an external display, so the first
/// question of issue #147, where the delay on a TV actually comes from, can be
/// answered by measuring instead of guessing.
///
/// Three things matter and none of them were visible before: whether the app
/// paints the display itself and at which size and scale, what the audio route
/// costs (`outputLatency` is the figure that jumps the moment AirPlay takes
/// over), and whether the second output path costs frames.
///
/// Why `Logger.performance` and not `os_signpost`: the setup under test is a
/// phone on a TV in a living room, and the performance channel already has a
/// switch in Settings and is readable in Console.app without a tethered Mac or
/// an Instruments trace. Signposts would be the better tool for a per-frame
/// profile at a desk, which is not where this problem shows itself.
///
/// What it costs: one route observer and a handful of lines per game, and while
/// a display is actually being painted a counter plus one clock read per frame.
/// Nothing at all runs per frame while the game stays on the phone.
@MainActor
final class ExternalDisplayDiagnostics {

    static let shared = ExternalDisplayDiagnostics()

    private var frameRate = ExternalFrameRateCounter()
    private var routeObserver: NSObjectProtocol?

    /// Size of what we are currently painting, carried along so the frame rate
    /// line says which output the frames went to.
    private var renderedSize: String?

    // MARK: - Session lifecycle

    /// Audio routes are watched for as long as a game runs, not just while a
    /// display is attached: AirPlay moves the audio before, and sometimes
    /// without, a display scene ever arriving, and that move is exactly when the
    /// output latency jumps.
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
        renderedSize = nil
    }

    // MARK: - Display lifecycle

    func displayDidConnect(_ scene: UIWindowScene) {
        let screen = scene.screen
        Logger.performance.info(String(
            format: "external display connected: %.0fx%.0f pt at %.1fx (%.0fx%.0f px), up to %ld Hz",
            screen.bounds.width, screen.bounds.height, screen.scale,
            screen.nativeBounds.width, screen.nativeBounds.height,
            screen.maximumFramesPerSecond
        ))
        // The route as it stands with the display attached. Over AirPlay the
        // audio usually moved a moment earlier, so this is the reading to
        // compare against the one from `sessionDidBegin`.
        Self.logAudioRoute("with the display attached")
    }

    func displayDidDisconnect() {
        Logger.performance.info("external display disconnected")
        Self.logAudioRoute("after the display went away")
    }

    /// The app now owns the display. The alternative, plain system mirroring,
    /// produces no frames of ours at all, which is what makes the rate below
    /// meaningful as a comparison.
    /// - Parameter countingFrames: Whether the renderer in charge reports its
    ///   frames. Said out loud because the absence of a rate line afterwards
    ///   otherwise reads as a rate of zero.
    func renderingDidStart(on scene: UIWindowScene, countingFrames: Bool) {
        let screen = scene.screen
        renderedSize = String(
            format: "%.0fx%.0f at %.1fx",
            screen.bounds.width, screen.bounds.height, screen.scale
        )
        frameRate.reset()
        let counting = countingFrames ? "" : ", frames not counted on this path"
        Logger.performance.info("painting the external display ourselves, \(renderedSize ?? "")\(counting)")
    }

    func renderingDidStop() {
        guard renderedSize != nil else { return }
        renderedSize = nil
        frameRate.reset()
        Logger.performance.info("external display released back to mirroring")
    }

    // MARK: - Frames

    /// Called once per frame that reached the external surface. Whether the
    /// second output path costs frames is only visible next to the phone's own
    /// rate, which the pacing diagnostics in `LibretroFrontend` already report.
    func externalFrameRendered() {
        guard let rate = frameRate.record(at: CACurrentMediaTime()) else { return }
        Logger.performance.debug(String(
            format: "external video: %.2f frames/s to %@, audio out latency %.1f ms",
            rate,
            renderedSize ?? "the external display",
            AVAudioSession.sharedInstance().outputLatency * 1000
        ))
    }

    // MARK: - Helpers

    private static func logAudioRoute(_ occasion: String) {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ", ")
        // `outputLatency` is the one the AirPlay hop lands in: it counts the way
        // from the app's mixer to the speaker, so a value in the hundreds of
        // milliseconds means the delay is not ours to fix in the renderer.
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
/// Its own type so the arithmetic can be tested without a display, and because
/// the per-frame call site must stay free of anything but counting.
struct ExternalFrameRateCounter {

    /// Seconds a window has to cover before a rate is worth reporting. Shorter
    /// windows make a single late frame look like a rate collapse.
    static let windowSeconds: CFTimeInterval = 1

    /// A gap longer than this is not a slow frame, it is the game standing
    /// still: the in-game menu, a pause, the app in the background. Counting
    /// through it would report the pause as a rate collapse on the frame the
    /// player comes back to.
    static let pauseSeconds: CFTimeInterval = 0.5

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
