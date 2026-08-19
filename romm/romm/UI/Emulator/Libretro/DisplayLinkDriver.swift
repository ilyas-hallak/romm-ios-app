import QuartzCore

/// Drives the emulator from the display's own refresh signal.
///
/// Replaces a `DispatchSourceTimer`, which had two costs. It fired with no
/// relation to the screen, so a frame finished right after a refresh sat around
/// for most of a refresh cycle before being composited, half a frame of latency
/// on average. And without an explicit `leeway` the system is free to coalesce
/// timer firings to save power, which produces exactly the uneven frame pacing
/// AirPlay tolerates least: the receiver's jitter buffer has to be sized for the
/// worst gap, so steady frames let it stay small.
///
/// `CADisplayLink` lands the work just before the next refresh instead, and
/// cannot be coalesced.
///
/// Exists as its own NSObject because `CADisplayLink` needs an `@objc` selector,
/// which a plain Swift class such as `LibretroFrontend` cannot offer.
final class DisplayLinkDriver: NSObject {

    /// Passed the duration of the upcoming display frame, so the caller can pace
    /// a core whose rate differs from the screen's (120 Hz panel, 50 Hz PAL core).
    private let onTick: (CFTimeInterval) -> Void

    private var link: CADisplayLink?

    init(preferredFPS: Double, onTick: @escaping (CFTimeInterval) -> Void) {
        self.onTick = onTick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // Asking for the core's rate keeps ProMotion from running the callback at
        // 120 Hz just to have most ticks do nothing. The caller's accumulator
        // still copes if the system picks something else.
        let fps = Float(preferredFPS)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        self.link = link
    }

    func start() {
        link?.add(to: .main, forMode: .common)
    }

    var isPaused: Bool {
        get { link?.isPaused ?? true }
        set { link?.isPaused = newValue }
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }

    /// Delivered on the main thread because the link is scheduled on the main
    /// run loop, which is what lets the callback run without an actor hop.
    @objc private func tick(_ link: CADisplayLink) {
        let duration = link.targetTimestamp - link.timestamp
        onTick(duration > 0 ? duration : 1.0 / 60.0)
    }
}
