import AVFoundation

/// Shared audio session setup for all three emulator engines.
///
/// `.playback` is what makes a running game behave like a media app: it ignores
/// the ring switch, so muting the phone no longer mutes the console, and it
/// leaves the volume entirely to the hardware buttons. Activating without
/// `.mixWithOthers` also stops whatever else was playing, which matters beyond
/// the obvious: DeltaCore silences its own mixer for as long as another app
/// holds the audio, so a game started over a running podcast would come up mute.
enum EmulatorAudioSession {

    /// - Parameter preferredIOBufferDuration: Hardware buffer size to ask for,
    ///   in seconds. Has to be requested before the session goes active, so it
    ///   belongs here rather than at the call site.
    static func activate(preferredIOBufferDuration: TimeInterval? = nil) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            if let preferredIOBufferDuration {
                try session.setPreferredIOBufferDuration(preferredIOBufferDuration)
            }
            try session.setActive(true, options: [])
        } catch {
            Logger.ui.error("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    /// Takes the category back after DeltaCore has claimed it.
    ///
    /// `AudioManager.start()` overwrites it with `.playAndRecord` and
    /// `[.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay]` while the core
    /// comes up, so the setting made above survives exactly until emulation
    /// begins. That category opens an input next to the output, which costs I/O
    /// latency and routes by different rules (without `.defaultToSpeaker` it can
    /// even land on the receiver), and over AirPlay that is latency stacked on
    /// top of the wireless hop. `Vendor/` is never forked, so it is corrected
    /// from the outside once the core has had its say. DeltaCore only sets the
    /// category in its `init` and in `start()`, never again on a route change,
    /// so one correction afterwards holds for the session.
    ///
    /// Only the category is set here, deliberately. Re-activating the session
    /// would re-open the "is another app playing" question that DeltaCore
    /// answers once at start, and that answer decides whether the game can be
    /// heard at all, see `NativeEmulatorSession.refreshOutputVolume()`.
    static func restorePlaybackCategory() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playback else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            Logger.performance.info(String(
                format: "audio category reclaimed as .playback, io buffer %.1f ms, out latency %.1f ms",
                session.ioBufferDuration * 1000, session.outputLatency * 1000
            ))
        } catch {
            Logger.ui.error("Audio category could not be set back to playback: \(error.localizedDescription)")
        }
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Logger.ui.error("Audio session deactivation failed: \(error.localizedDescription)")
        }
    }
}
