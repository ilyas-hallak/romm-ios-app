import Foundation
import AVFoundation

extension LibretroFrontend {

    // MARK: - Audio ring buffer
    /// 2 Sekunden Stereo @ 44.1 kHz. Reicht für Drift zwischen Core-FPS und
    /// AVAudioEngine-Render ohne dass der Producer den Reader überholt.
    private static let audioSampleRateHz = 44_100
    private static let audioChannelCount = 2
    private static let audioRingBufferSeconds = 2
    /// Shared ringbuffer + idx werden vom Audio-Thread (renderAudio) und MainActor
    /// (enqueueAudio) gemeinsam genutzt. NSLock schützt vor Race.
    nonisolated(unsafe) static let audioRingLock = NSLock()
    nonisolated(unsafe) static var audioRing: [Int16] = Array(
        repeating: 0,
        count: audioSampleRateHz * audioChannelCount * audioRingBufferSeconds
    )
    nonisolated(unsafe) static var audioWriteIdx: Int = 0
    nonisolated(unsafe) static var audioReadIdx: Int = 0
    /// The core's actual rate, needed to turn a sample count into a duration.
    nonisolated(unsafe) static var audioActiveSampleRate: Double = 44_100

    /// Trim window. The fill level sawtooths between target and threshold, so the
    /// average latency is roughly their midpoint and both numbers matter.
    ///
    /// Kept deliberately tight: the core hands over one block of about 16.7 ms per
    /// frame, so a target of 50 ms still holds three blocks in reserve against
    /// frame jitter. Going lower starts to risk underruns, which `audioUnderruns`
    /// counts so the trade-off can be checked rather than guessed at.
    private static let audioTrimThresholdMs: Double = 80
    private static let audioTrimTargetMs: Double = 50

    /// Incremented whenever the render callback runs out of samples and has to
    /// emit silence. Anything above zero during steady play means the trim window
    /// is too tight.
    nonisolated(unsafe) static var audioUnderruns: Int = 0

    /// How much audio is waiting to be played. This, not the ring's size, is the
    /// audio latency: the ring is 2 seconds deep, what matters is how full it is.
    func audioBufferedMilliseconds() -> Double {
        Self.audioRingLock.lock()
        let queued = (Self.audioWriteIdx - Self.audioReadIdx + Self.audioRing.count) % Self.audioRing.count
        Self.audioRingLock.unlock()
        return Double(queued) / Double(Self.audioChannelCount) / Self.audioActiveSampleRate * 1000
    }

    func startAudio(sampleRate: Double) {
        Self.audioActiveSampleRate = sampleRate > 0 ? sampleRate : Double(Self.audioSampleRateHz)
        Self.audioUnderruns = 0
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        // Ask for a short hardware buffer. The default under .playback is around
        // 20 ms, chosen for power rather than latency, and every millisecond here
        // is a millisecond between the core producing a sample and it being
        // heard. The render callback only copies out of a ring, so it can
        // comfortably run this often. The system may grant less than asked, and
        // over AirPlay it usually ignores this entirely, hence the log below.
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true, options: [])
        print(String(
            format: "[Libretro] audio out: io buffer %.1f ms, route latency %.1f ms",
            session.ioBufferDuration * 1000, session.outputLatency * 1000
        ))

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let node = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            return Self.renderAudio(into: abl, frameCount: Int(frameCount))
        }
        audioSourceNode = node
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)
        do {
            try audioEngine.start()
            print("[Libretro] audio engine started @\(sampleRate)Hz")
        } catch {
            print("[Libretro] audio start failed: \(error)")
        }
    }

    func stopAudio() {
        audioEngine.stop()
        if let node = audioSourceNode {
            audioEngine.detach(node)
            audioSourceNode = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Drops any buffered samples by collapsing the read cursor onto the write
    /// cursor. Called right after loading a save state: the ring still holds the
    /// audio produced before the load (e.g. the boot/intro that ran while the
    /// core warmed up), and playing it out would leave sound permanently lagging
    /// the picture.
    func flushAudio() {
        Self.audioRingLock.lock()
        Self.audioReadIdx = Self.audioWriteIdx
        Self.audioRingLock.unlock()
    }

    func pauseAudio() {
        audioEngine.pause()
    }

    func resumeAudio() {
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
    }

    func enqueueAudio(_ samples: UnsafePointer<Int16>, frames: Int) {
        let count = frames * 2 // stereo
        Self.audioRingLock.lock()
        for i in 0..<count {
            Self.audioRing[Self.audioWriteIdx] = samples[i]
            Self.audioWriteIdx = (Self.audioWriteIdx + 1) % Self.audioRing.count
            if Self.audioWriteIdx == Self.audioReadIdx {
                Self.audioReadIdx = (Self.audioReadIdx + 1) % Self.audioRing.count
            }
        }

        // Trimmed inside the same critical section: the render callback contends
        // for this lock on the audio thread, so taking it again just to check a
        // level would risk the dropouts we are trying to avoid.
        //
        // Why trim at all: if the core produces even slightly faster than the
        // engine consumes, the fill level creeps up and the sound ends up
        // permanently behind the picture, until the ring wraps and jumps. One
        // small discontinuity is far less noticeable than a growing offset.
        let samplesPerMs = Self.audioActiveSampleRate / 1000 * Double(Self.audioChannelCount)
        let threshold = Int(Self.audioTrimThresholdMs * samplesPerMs)
        let target = Int(Self.audioTrimTargetMs * samplesPerMs)
        let queued = (Self.audioWriteIdx - Self.audioReadIdx + Self.audioRing.count) % Self.audioRing.count
        if queued > threshold {
            // Advance the reader rather than rewinding the writer: the newest
            // audio is the part that belongs with the picture on screen now.
            Self.audioReadIdx = (Self.audioWriteIdx - target + Self.audioRing.count) % Self.audioRing.count
        }
        Self.audioRingLock.unlock()
    }

    nonisolated static func renderAudio(into abl: UnsafeMutableAudioBufferListPointer, frameCount: Int) -> OSStatus {
        let left = abl[0].mData!.assumingMemoryBound(to: Float.self)
        let right = abl.count > 1 ? abl[1].mData!.assumingMemoryBound(to: Float.self) : nil
        let interleaved = right == nil

        audioRingLock.lock()
        if interleaved {
            let needed = frameCount * 2
            var i = 0
            while i < needed && audioReadIdx != audioWriteIdx {
                left[i] = Float(audioRing[audioReadIdx]) / 32768.0
                audioReadIdx = (audioReadIdx + 1) % audioRing.count
                i += 1
            }
            if i < needed { audioUnderruns += 1 }
            while i < needed { left[i] = 0; i += 1 }
        } else {
            var fi = 0
            while fi < frameCount && audioReadIdx != audioWriteIdx {
                left[fi] = Float(audioRing[audioReadIdx]) / 32768.0
                audioReadIdx = (audioReadIdx + 1) % audioRing.count
                if audioReadIdx == audioWriteIdx { right![fi] = 0; fi += 1; break }
                right![fi] = Float(audioRing[audioReadIdx]) / 32768.0
                audioReadIdx = (audioReadIdx + 1) % audioRing.count
                fi += 1
            }
            if fi < frameCount { audioUnderruns += 1 }
            while fi < frameCount { left[fi] = 0; right![fi] = 0; fi += 1 }
        }
        audioRingLock.unlock()
        return noErr
    }
}
