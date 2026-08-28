import CoreHaptics
import GameController
import UIKit

/// Turns the two motor channels a core reports into actual haptic feedback.
///
/// Two output paths, picked automatically:
/// - A physical controller that has haptics gets one `CHHapticEngine` per handle
///   via `GCDeviceHaptics.createEngine(withLocality:)`, so the strong (low
///   frequency) and the weak (high frequency) motor stay independent. Pads that
///   cannot address the handles separately fall back to a single engine driven
///   with the louder of the two channels.
/// - Without such a controller the phone's own haptics stand in, again as a
///   single combined channel. On hardware without haptics (iPad, tvOS) the class
///   simply does nothing.
///
/// `setMotors` is meant to be called from the emulation loop, up to 60 times a
/// second and usually with the value it already has, so the hot path is a couple
/// of comparisons and an early return. Only a real change reaches Core Haptics,
/// and then only as a dynamic parameter on an already running player, which is
/// far cheaper than starting one.
///
/// Nothing in here is allowed to disturb emulation: every Core Haptics call can
/// throw and every failure is swallowed, at most it is logged once.
@MainActor
final class RumbleOutput {

    // MARK: - Tuning

    /// Sharpness for the big low frequency motor. Low value, that is what makes
    /// it feel like a rumble rather than a tick.
    private static let strongSharpness: Float = 0.15
    /// Sharpness for the small high frequency motor.
    private static let weakSharpness: Float = 0.85
    /// Sharpness used when both channels share one motor.
    private static let combinedSharpness: Float = 0.5

    // MARK: - Public API

    /// Factor every motor strength is multiplied with, clamped to 0...1.
    /// Changing it re-applies the current motor levels right away.
    var scale: Float {
        get { storedScale }
        set {
            let clamped = Self.normalized(newValue)
            guard clamped != storedScale else { return }
            storedScale = clamped
            applyMotors()
        }
    }

    init() {}

    /// Builds the haptic engines for the currently selected output and starts
    /// listening for app lifecycle changes. Idempotent.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        registerLifecycleObservers()
        buildChannels()
    }

    /// Stops all motors, tears the engines down and stops listening. Idempotent.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        unregisterLifecycleObservers()
        rawStrong = 0
        rawWeak = 0
        silenceChannels()
        tearDownChannels()
    }

    /// Selects the physical controller the output goes to. Passing nil, or a
    /// controller without haptics support, routes to the device haptics instead.
    ///
    /// The motors of the outgoing controller are set to zero before its engines
    /// go away: a pad keeps buzzing on its own once it has been told to, and
    /// nobody is left to tell it otherwise.
    func attach(controller: GCController?) {
        guard controller !== attachedController else { return }
        silenceChannels()
        tearDownChannels()
        attachedController = controller
        guard isStarted else { return }
        buildChannels()
        applyMotors()
    }

    /// Sets the current motor strengths, each 0...1 and without `scale` applied.
    ///
    /// Safe to call every frame: identical values are dropped here, and values
    /// that moved by less than one 8 bit step are dropped further down before
    /// they reach the engine.
    func setMotors(strong: Float, weak: Float) {
        let normalizedStrong = Self.normalized(strong)
        let normalizedWeak = Self.normalized(weak)
        guard normalizedStrong != rawStrong || normalizedWeak != rawWeak else { return }
        rawStrong = normalizedStrong
        rawWeak = normalizedWeak
        applyMotors()
    }

    // MARK: - State

    private var storedScale: Float = 1

    /// Motor levels as reported by the core, before `scale`.
    private var rawStrong: Float = 0
    private var rawWeak: Float = 0

    private var isStarted = false
    private var attachedController: GCController?

    /// Either the separate pair (strong + weak) or the combined channel is in
    /// use, never both.
    private var strongChannel: RumbleChannel?
    private var weakChannel: RumbleChannel?
    private var combinedChannel: RumbleChannel?

    private var lifecycleObservers: [NSObjectProtocol] = []

    // MARK: - Applying levels

    private func applyMotors() {
        let strong = rawStrong * storedScale
        let weak = rawWeak * storedScale
        if let combinedChannel {
            // One motor for both channels, so the stronger of the two wins.
            // Adding them up would saturate at the slightest bit of rumble.
            combinedChannel.setIntensity(max(strong, weak))
        } else {
            strongChannel?.setIntensity(strong)
            weakChannel?.setIntensity(weak)
        }
    }

    private func silenceChannels() {
        strongChannel?.setIntensity(0)
        weakChannel?.setIntensity(0)
        combinedChannel?.setIntensity(0)
    }

    /// Clamps to 0...1 and turns NaN or infinity into silence. A core reporting
    /// garbage must not be able to leave a motor stuck at full power.
    private static func normalized(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    // MARK: - Building the channels

    private func buildChannels() {
        if let attachedController, buildControllerChannels(for: attachedController) { return }
        buildDeviceChannel()
    }

    /// - Returns: true when the controller could supply at least one engine.
    ///   false means the caller should fall back to the device haptics.
    private func buildControllerChannels(for controller: GCController) -> Bool {
        guard let haptics = controller.haptics else { return false }
        let localities = haptics.supportedLocalities

        // Preferred layout: one engine per handle. strong drives the big low
        // frequency motor on the left, weak the small high frequency one on the
        // right, matching how cores label the two channels.
        if localities.contains(.leftHandle), localities.contains(.rightHandle),
           let left = haptics.createEngine(withLocality: .leftHandle),
           let right = haptics.createEngine(withLocality: .rightHandle) {
            strongChannel = RumbleChannel(engine: left, sharpness: Self.strongSharpness, kind: .controller)
            weakChannel = RumbleChannel(engine: right, sharpness: Self.weakSharpness, kind: .controller)
            startChannels()
            log("controller haptics on separate handles")
            return true
        }

        // The pad cannot address the handles individually, so both channels go
        // into a single engine.
        for locality in [GCHapticsLocality.default, .all] where localities.contains(locality) {
            guard let engine = haptics.createEngine(withLocality: locality) else { continue }
            combinedChannel = RumbleChannel(engine: engine, sharpness: Self.combinedSharpness, kind: .controller)
            startChannels()
            log("controller haptics combined on \(locality.rawValue)")
            return true
        }

        return false
    }

    private func buildDeviceChannel() {
        #if os(iOS)
        // iPads and older iPhones have no haptic hardware, and tvOS has none at
        // all, so this path just stays empty there.
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            combinedChannel = RumbleChannel(engine: engine, sharpness: Self.combinedSharpness, kind: .device)
            startChannels()
        } catch {
            log("device engine unavailable: \(error.localizedDescription)")
        }
        #endif
    }

    private func startChannels() {
        strongChannel?.start()
        weakChannel?.start()
        combinedChannel?.start()
    }

    private func tearDownChannels() {
        strongChannel?.stop()
        weakChannel?.stop()
        combinedChannel?.stop()
        strongChannel = nil
        weakChannel = nil
        combinedChannel = nil
    }

    // MARK: - App lifecycle

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default
        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnterBackground() }
        }
        let foreground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleEnterForeground() }
        }
        lifecycleObservers = [background, foreground]
    }

    private func unregisterLifecycleObservers() {
        let center = NotificationCenter.default
        for observer in lifecycleObservers {
            center.removeObserver(observer)
        }
        lifecycleObservers = []
    }

    /// Silence first, release the engines second. The other order can leave a
    /// controller humming while the app is in the background.
    private func handleEnterBackground() {
        silenceChannels()
        tearDownChannels()
    }

    private func handleEnterForeground() {
        guard isStarted else { return }
        buildChannels()
        applyMotors()
    }

    // MARK: - Logging

    /// Deliberately sparse: never per frame, only on lifecycle events and on
    /// failures that a developer would otherwise spend an evening chasing.
    fileprivate static func log(_ message: String) {
        print("[Rumble] \(message)")
    }

    private func log(_ message: String) {
        Self.log(message)
    }

    deinit {
        // Block based observers are not removed automatically. The blocks only
        // capture self weakly, so this is about not leaving dead registrations
        // behind rather than about correctness.
        let center = NotificationCenter.default
        for observer in lifecycleObservers {
            center.removeObserver(observer)
        }
    }
}

// MARK: - One motor, one engine

/// A single continuously running motor backed by one `CHHapticEngine`.
///
/// The event itself is created at full intensity and the live level is applied
/// on top of it as a `.hapticIntensityControl` dynamic parameter. Core Haptics
/// multiplies the two, so an event that started at zero could never be turned
/// back up, the dynamic parameter has to modulate something non-zero.
///
/// The player is created lazily on the first non-zero level, because starting a
/// player has noticeable latency while `sendParameters` is close to free, and it
/// is torn down again after the motor has been silent for a moment so an idle
/// game does not keep the hardware awake.
@MainActor
private final class RumbleChannel {

    /// Which kind of hardware this channel drives. The two differ in what Core
    /// Haptics allows, not just in where the buzz comes out.
    enum Kind {
        /// A `CHHapticEngine` vended by GameController. It refuses to create a
        /// `CHHapticAdvancedPatternPlayer`, so there is no `loopEnabled` here and
        /// the plain player has to be restarted before its event runs out.
        case controller
        /// The device's own engine, where an advanced looping player is fine.
        case device

        var isLooping: Bool { self == .device }
    }

    /// Longest duration Core Haptics accepts for a single continuous event.
    private static let maxEventDuration: TimeInterval = 30
    /// When the plain player is restarted. Comfortably inside the event so the
    /// seam falls into a still-running pattern instead of after a gap.
    private static let restartInterval: TimeInterval = 25
    /// Changes below one 8 bit step are not worth a round trip to the engine.
    private static let epsilon: Float = 1.0 / 255.0
    /// How long the motor has to stay silent before the player is released.
    private static let idleShutdownDelay: TimeInterval = 1.0

    private let engine: CHHapticEngine
    private let sharpness: Float
    private let kind: Kind

    private var player: CHHapticPatternPlayer?
    private var isPlaying = false
    private var isEngineRunning = false
    /// Set once `engine.start()` has failed, so a core hammering setMotors does
    /// not retry (and log) sixty times a second.
    private var startFailed = false
    /// Last level handed to the engine, already scaled.
    private var intensity: Float = 0

    private var restartTimer: Timer?
    private var idleTimer: Timer?

    init(engine: CHHapticEngine, sharpness: Float, kind: Kind) {
        self.engine = engine
        self.sharpness = sharpness
        self.kind = kind
    }

    // MARK: - Lifecycle

    /// Installs the recovery handlers and starts the engine. Idempotent.
    func start() {
        guard !isEngineRunning, !startFailed else { return }

        // The engine is kept alive for the whole session instead of being shut
        // down between bursts of rumble: waking it up again costs latency the
        // player start already pays for, and the app stops it explicitly on
        // stop() and when going to the background.
        engine.isAutoShutdownEnabled = false
        if kind == .device {
            // Keeps the device engine out of the audio session so it cannot duck
            // or interrupt the emulator's own audio.
            engine.playsHapticsOnly = true
        }

        engine.resetHandler = { [weak self] in
            Task { @MainActor in self?.handleReset() }
        }
        engine.stoppedHandler = { [weak self] reason in
            Task { @MainActor in self?.handleStopped(reason) }
        }

        do {
            try engine.start()
            isEngineRunning = true
        } catch {
            startFailed = true
            RumbleOutput.log("engine start failed: \(error.localizedDescription)")
        }
    }

    /// Stops the motor, the player and the engine. Idempotent.
    func stop() {
        intensity = 0
        sendIntensity(0)
        cancelIdleStop()
        stopPlayer()
        // The handlers are not optional, so they are replaced rather than
        // cleared. Dropping the ones that capture self before stopping the
        // engine keeps our own shutdown from looking like an unexpected stop.
        engine.resetHandler = {}
        engine.stoppedHandler = { _ in }
        guard isEngineRunning else { return }
        isEngineRunning = false
        engine.stop { _ in }
    }

    // MARK: - Level

    /// Applies a new level, 0...1 and already scaled.
    func setIntensity(_ value: Float) {
        let isSilent = value <= 0
        let wasSilent = intensity <= 0
        // A transition into or out of silence always counts, even if the numeric
        // step is tiny, otherwise a motor could be left quietly humming.
        guard isSilent != wasSilent || abs(value - intensity) >= Self.epsilon else { return }
        intensity = value

        if isSilent {
            sendIntensity(0)
            scheduleIdleStop()
        } else {
            cancelIdleStop()
            ensurePlaying()
            sendIntensity(value)
        }
    }

    private func sendIntensity(_ value: Float) {
        guard isPlaying, let player else { return }
        let parameter = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: value,
            relativeTime: 0
        )
        do {
            try player.sendParameters([parameter], atTime: CHHapticTimeImmediate)
        } catch {
            // Intentionally silent: this runs on every motor change and must
            // neither flood the log nor interrupt emulation.
        }
    }

    // MARK: - Player

    private func ensurePlaying() {
        if !isEngineRunning { start() }
        guard isEngineRunning, !isPlaying else { return }
        guard let newPlayer = makePlayer() else { return }
        do {
            try newPlayer.start(atTime: CHHapticTimeImmediate)
            player = newPlayer
            isPlaying = true
            armRestartTimer()
        } catch {
            RumbleOutput.log("player start failed: \(error.localizedDescription)")
        }
    }

    private func makePlayer() -> CHHapticPatternPlayer? {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: 0,
            duration: Self.maxEventDuration
        )
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            guard kind.isLooping else {
                return try engine.makePlayer(with: pattern)
            }
            let advanced = try engine.makeAdvancedPlayer(with: pattern)
            advanced.loopEnabled = true
            return advanced
        } catch {
            RumbleOutput.log("player creation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func stopPlayer() {
        restartTimer?.invalidate()
        restartTimer = nil
        if isPlaying, let player {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        player = nil
        isPlaying = false
    }

    /// Only the controller path needs this: its plain player cannot loop, and a
    /// continuous event may not exceed `maxEventDuration`, so a long rumble has
    /// to be handed over to a fresh player before the old one runs dry.
    private func armRestartTimer() {
        guard !kind.isLooping else { return }
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(
            withTimeInterval: Self.restartInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.restartPlayer() }
        }
    }

    /// Rebuilds the player and brings it straight back to the current level.
    /// `ensurePlaying` arms the next restart, so this keeps going for as long as
    /// the motor is running.
    private func restartPlayer() {
        restartTimer = nil
        guard isPlaying, intensity > 0 else { return }
        stopPlayer()
        ensurePlaying()
        sendIntensity(intensity)
    }

    // MARK: - Idle shutdown

    private func scheduleIdleStop() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: Self.idleShutdownDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.stopIfStillIdle() }
        }
    }

    private func cancelIdleStop() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func stopIfStillIdle() {
        idleTimer = nil
        guard intensity <= 0 else { return }
        stopPlayer()
    }

    // MARK: - Engine recovery

    /// The system tore the engine down and rebuilt it, so everything that was
    /// playing is gone. Without this the rumble would die silently and only come
    /// back on the next app launch.
    private func handleReset() {
        forgetPlayer()
        RumbleOutput.log("engine reset, rebuilding")
        startFailed = false
        start()
        resumeIfNeeded()
    }

    /// The engine stopped on its own, typically an audio session interrupt or
    /// the app being suspended.
    private func handleStopped(_ reason: CHHapticEngine.StoppedReason) {
        forgetPlayer()

        switch reason {
        case .applicationSuspended, .engineDestroyed, .gameControllerDisconnect:
            // Nothing worth recovering: the app is going away, the engine is
            // gone, or the pad left. The foreground notification and attach()
            // rebuild whatever is needed.
            return
        default:
            break
        }

        RumbleOutput.log("engine stopped (reason \(reason.rawValue)), restarting")
        startFailed = false
        start()
        resumeIfNeeded()
    }

    private func forgetPlayer() {
        restartTimer?.invalidate()
        restartTimer = nil
        player = nil
        isPlaying = false
        isEngineRunning = false
    }

    private func resumeIfNeeded() {
        guard intensity > 0 else { return }
        ensurePlaying()
        sendIntensity(intensity)
    }
}
