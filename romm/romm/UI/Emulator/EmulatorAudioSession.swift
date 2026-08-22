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

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            Logger.ui.error("Audio session deactivation failed: \(error.localizedDescription)")
        }
    }
}
