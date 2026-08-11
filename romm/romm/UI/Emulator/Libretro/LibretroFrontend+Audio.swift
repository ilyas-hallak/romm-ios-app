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

    func startAudio(sampleRate: Double) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true, options: [])

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
            while fi < frameCount { left[fi] = 0; right![fi] = 0; fi += 1 }
        }
        audioRingLock.unlock()
        return noErr
    }
}
