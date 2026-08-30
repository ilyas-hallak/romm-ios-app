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

    /// Fill level from which the core counts as running ahead of the audio
    /// clock.
    ///
    /// Note what this cannot do, measured rather than assumed: the trim below
    /// runs inside `enqueueAudio`, so the level is already back at the target
    /// by the time the next tick reads it. With a core handing over 33 ms per
    /// call the level sawtooths between roughly 33 and 50 ms and never reaches
    /// this limit — the device log showed exactly that, `0 throttled` while the
    /// game ran at double speed. Back pressure is a safety net against a core
    /// that outruns us in bursts, not a speed regulator; getting the emulated
    /// time per `retro_run` right is the frontend's job (see the PPSSPP
    /// `ppsspp_frame_duplication` answer in LibretroFrontend+Environment).
    private static let audioRunAheadLimitMs: Double = 70

    /// Whether the next `retro_run` would only produce samples the trim is going
    /// to throw away again.
    ///
    /// The samples a core hands over are proportional to *emulated* time, which
    /// makes a ring that keeps filling the one reliable signal that the core is
    /// running faster than real time — the frame counter cannot see it, because
    /// a core that advances two emulated frames per call still looks like a
    /// perfect 60 fps from the outside.
    ///
    /// Only meaningful while the engine actually drains the ring. With no
    /// consumer the trim in `enqueueAudio` parks the fill level inside the
    /// window all by itself, and reading it would stall the core for good.
    func coreIsAheadOfAudio() -> Bool {
        guard audioEngine.isRunning else { return false }
        return audioBufferedMilliseconds() >= Self.audioRunAheadLimitMs
    }

    /// Incremented whenever the render callback runs out of samples and has to
    /// emit silence. Anything above zero during steady play means the trim window
    /// is too tight.
    nonisolated(unsafe) static var audioUnderruns: Int = 0

    /// Frames (sample pairs) handed over by the core since the last pacing
    /// report, and frames the trim threw away again in the same window.
    ///
    /// The production rate is the only direct measure of *emulated* time we get:
    /// cores schedule their mixer off the emulated clock (PPSSPP every 64
    /// samples, `__sceAudio.cpp:63`), so 44100 frames per real second means the
    /// core is running at real time and 88200 means double speed. The frame
    /// counter cannot show this, because a core that advances two emulated
    /// frames per `retro_run` still looks like a clean 60 fps from outside.
    ///
    /// The trim counter belongs next to it: while it is discarding samples the
    /// fill level says nothing about the production rate, and every regulation
    /// built on that level — `coreIsAheadOfAudio()` included — is reading a
    /// number the trim itself has pinned inside its window.
    ///
    /// Counted per batch (about 60 calls a second), not per sample.
    nonisolated(unsafe) static var audioFramesProduced: Int = 0
    nonisolated(unsafe) static var audioFramesTrimmed: Int = 0

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
        Self.audioFramesProduced = 0
        Self.audioFramesTrimmed = 0
        // Ask for a short hardware buffer. The default under .playback is around
        // 20 ms, chosen for power rather than latency, and every millisecond here
        // is a millisecond between the core producing a sample and it being
        // heard. The render callback only copies out of a ring, so it can
        // comfortably run this often. The system may grant less than asked, and
        // over AirPlay it usually ignores this entirely, hence the log below.
        EmulatorAudioSession.activate(preferredIOBufferDuration: 0.005)
        let session = AVAudioSession.sharedInstance()
        // Core rate and hardware rate are logged side by side because they
        // differ on every iPhone (cores are 44.1 kHz, the built-in speaker runs
        // at 48 kHz). The conversion is the mixer's job below, and this line is
        // what shows whether it is actually happening.
        print(String(
            format: "[Libretro] audio out: core %.0f Hz, hardware %.0f Hz, io buffer %.1f ms, route latency %.1f ms",
            sampleRate, session.sampleRate, session.ioBufferDuration * 1000, session.outputLatency * 1000
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
            // The source node is created without a format, so the render block
            // is driven at the connection format above — the mixer resamples to
            // the output rate. If those two ever printed the same rate while the
            // hardware ran at another, the block would be pulled at the wrong
            // speed and everything would play sharp.
            print(String(
                format: "[Libretro] audio graph: source %.0f Hz -> mixer out %.0f Hz -> device %.0f Hz",
                sampleRate,
                audioEngine.mainMixerNode.outputFormat(forBus: 0).sampleRate,
                audioEngine.outputNode.outputFormat(forBus: 0).sampleRate
            ))
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
        EmulatorAudioSession.deactivate()
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
        Self.audioFramesProduced += frames
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
            Self.audioFramesTrimmed += (queued - target) / Self.audioChannelCount
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
