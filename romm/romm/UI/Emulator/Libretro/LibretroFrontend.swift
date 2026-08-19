import Foundation
import Darwin
import AVFoundation

/// Minimaler libretro-Frontend: dlopen + Symbolauflösung + Run-Loop.
///
/// Implementiert die 5 Core-Callbacks als statische C-Funktionspointer, die
/// auf einen Singleton (`LibretroFrontend.shared`) zurückrouten. Singleton
/// ist nötig, weil `@convention(c)` keine Closure-Captures erlaubt — libretro
/// gibt uns keinen userdata-Pointer in `retro_set_environment`.
///
/// Status: PCSX ReARMed Bring-Up. Video als RGB565/XRGB8888 Software-Blit auf
/// ein CALayer (siehe `LibretroVideoView`). Audio TODO. Input TODO.
@MainActor
final class LibretroFrontend {

    // MARK: - Singleton (für C-Callbacks)
    static let shared = LibretroFrontend()
    private init() {}

    // MARK: - State
    private var handle: UnsafeMutableRawPointer?
    private var avInfo = LibretroABI.SystemAVInfo(
        geometry: .init(base_width: 0, base_height: 0, max_width: 0, max_height: 0, aspect_ratio: 0),
        timing: .init(fps: 60, sample_rate: 44100)
    )
    var pixelFormat: LibretroABI.PixelFormat = .rgb1555
    var systemDir: String = ""
    var saveDir: String = ""
    private var displayLink: DisplayLinkDriver?
    /// Carries leftover display time between ticks so a core whose rate differs
    /// from the screen's still runs at its own speed.
    private var frameAccumulator: Double = 0
    var frameCount: UInt64 = 0

    // Symbols
    private var retro_init: LibretroABI.RetroInit?
    private var retro_deinit: LibretroABI.RetroDeinit?
    private var retro_get_system_info: LibretroABI.RetroGetSystemInfo?
    private var retro_get_system_av_info: LibretroABI.RetroGetSystemAVInfo?
    private var retro_set_environment: LibretroABI.RetroSetEnvironment?
    private var retro_set_video_refresh: LibretroABI.RetroSetVideoRefresh?
    private var retro_set_audio_sample: LibretroABI.RetroSetAudioSample?
    private var retro_set_audio_sample_batch: LibretroABI.RetroSetAudioSampleBatch?
    private var retro_set_input_poll: LibretroABI.RetroSetInputPoll?
    private var retro_set_input_state: LibretroABI.RetroSetInputState?
    private var retro_set_controller_port_device: LibretroABI.RetroSetControllerPortDevice?
    private var retro_run: LibretroABI.RetroRun?
    private var retro_reset: LibretroABI.RetroReset?
    private var retro_load_game: LibretroABI.RetroLoadGame?
    private var retro_unload_game: LibretroABI.RetroUnloadGame?
    private var retro_serialize_size: LibretroABI.RetroSerializeSize?
    private var retro_serialize: LibretroABI.RetroSerialize?
    private var retro_unserialize: LibretroABI.RetroUnserialize?
    var retro_get_memory_data: LibretroABI.RetroGetMemoryData?
    var retro_get_memory_size: LibretroABI.RetroGetMemorySize?

    var sramURL: URL?

    weak var videoSink: LibretroVideoSink?

    // MARK: - Input state (Joypad port 0)
    /// Index = JoypadButton.rawValue. Atomar via MainActor-Isolation.
    var buttonState: [Bool] = Array(repeating: false, count: 16)

    func setButton(_ button: LibretroABI.JoypadButton, pressed: Bool) {
        buttonState[Int(button.rawValue)] = pressed
    }

    func clearAllButtons() {
        for i in 0..<buttonState.count { buttonState[i] = false }
    }

    // MARK: - Audio state (Implementation in LibretroFrontend+Audio.swift)
    let audioEngine = AVAudioEngine()
    var audioSourceNode: AVAudioSourceNode?

    // MARK: - Public API

    enum FrontendError: LocalizedError {
        case dylibNotFound(String)
        case symbolMissing(String)
        case loadGameFailed

        var errorDescription: String? {
            switch self {
            case .dylibNotFound(let path): return String(localized: "Dynamic library not found: \(path)")
            case .symbolMissing(let name): return String(localized: "Libretro symbol not found: \(name)")
            case .loadGameFailed: return String(localized: "retro_load_game failed.")
            }
        }

        var diagnosticDescription: String {
            switch self {
            case .dylibNotFound(let path): return "Dylib nicht gefunden: \(path)"
            case .symbolMissing(let name): return "Libretro-Symbol fehlt: \(name)"
            case .loadGameFailed: return "retro_load_game ist fehlgeschlagen."
            }
        }
    }

    func load(corePath: String, gamePath: String, systemDir: String, saveDir: String) throws {
        guard FileManager.default.fileExists(atPath: corePath) else {
            throw FrontendError.dylibNotFound(corePath)
        }
        try? FileManager.default.createDirectory(atPath: systemDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: saveDir, withIntermediateDirectories: true)
        self.systemDir = systemDir
        self.saveDir = saveDir

        guard let h = dlopen(corePath, RTLD_NOW | RTLD_LOCAL) else {
            let err = String(cString: dlerror())
            throw FrontendError.dylibNotFound("\(corePath) – \(err)")
        }
        self.handle = h

        try resolveSymbols()

        retro_set_environment?(Self.envCallback)
        retro_set_video_refresh?(Self.videoRefreshCallback)
        retro_set_audio_sample?(Self.audioSampleCallback)
        retro_set_audio_sample_batch?(Self.audioBatchCallback)
        retro_set_input_poll?(Self.inputPollCallback)
        retro_set_input_state?(Self.inputStateCallback)

        retro_init?()

        // Cores differ in how they want the game handed over: PCSX ReARMed loads
        // the disc by path itself (need_fullpath = true), while HuCard/cartridge
        // cores like Beetle PCE need the ROM bytes in memory (need_fullpath = false)
        // — otherwise they boot to a black screen.
        var sysInfo = LibretroABI.SystemInfo(
            library_name: nil,
            library_version: nil,
            valid_extensions: nil,
            need_fullpath: false,
            block_extract: false
        )
        withUnsafeMutablePointer(to: &sysInfo) { ptr in
            retro_get_system_info?(UnsafeMutableRawPointer(ptr))
        }
        print("[Libretro] need_fullpath=\(sysInfo.need_fullpath)")

        // cPath / data pointers must stay valid across the retro_load_game call.
        let loaded: Bool
        if sysInfo.need_fullpath {
            loaded = gamePath.withCString { cPath in
                var info = LibretroABI.GameInfo(path: cPath, data: nil, size: 0, meta: nil)
                return withUnsafePointer(to: &info) { ptr in
                    retro_load_game?(UnsafeRawPointer(ptr)) ?? false
                }
            }
        } else {
            let romData = try Data(contentsOf: URL(fileURLWithPath: gamePath))
            loaded = gamePath.withCString { cPath in
                romData.withUnsafeBytes { raw -> Bool in
                    var info = LibretroABI.GameInfo(
                        path: cPath,
                        data: raw.baseAddress,
                        size: romData.count,
                        meta: nil
                    )
                    return withUnsafePointer(to: &info) { ptr in
                        retro_load_game?(UnsafeRawPointer(ptr)) ?? false
                    }
                }
            }
        }
        guard loaded else { throw FrontendError.loadGameFailed }

        let romBase = (gamePath as NSString).lastPathComponent
        let stem = (romBase as NSString).deletingPathExtension
        self.sramURL = URL(fileURLWithPath: saveDir).appendingPathComponent("\(stem).srm")
        loadSRAMFromDisk()

        var av = LibretroABI.SystemAVInfo(
            geometry: .init(base_width: 0, base_height: 0, max_width: 0, max_height: 0, aspect_ratio: 0),
            timing: .init(fps: 60, sample_rate: 44100)
        )
        withUnsafeMutablePointer(to: &av) { ptr in
            retro_get_system_av_info?(UnsafeMutableRawPointer(ptr))
        }
        self.avInfo = av
        print("[Libretro] AV: \(av.geometry.base_width)x\(av.geometry.base_height) @\(av.timing.fps)Hz audio=\(av.timing.sample_rate)Hz")

        retro_set_controller_port_device?(0, LibretroABI.DEVICE_JOYPAD)

        startAudio(sampleRate: av.timing.sample_rate > 0 ? av.timing.sample_rate : 44100)
    }

    func startRunLoop() {
        frameAccumulator = 0
        frameRateWindowStart = 0
        frameRateWindowCount = 0
        let driver = DisplayLinkDriver { [weak self] displayFrameDuration in
            MainActor.assumeIsolated {
                self?.stepEmulation(displayFrameDuration: displayFrameDuration)
            }
        }
        displayLink = driver
        driver.start()
    }

    private var coreFPS: Double {
        avInfo.timing.fps > 0 ? avInfo.timing.fps : 60
    }

    /// Runs as many core frames as the elapsed display time calls for. Usually
    /// exactly one; zero on a 120 Hz panel every other tick, and two when the
    /// core is 60 Hz on a 50 Hz output.
    private func stepEmulation(displayFrameDuration: Double) {
        let coreInterval = 1.0 / coreFPS
        frameAccumulator += displayFrameDuration

        // Capped so that after a stall (a load, a resume) the backlog is not
        // burned off in one burst, which would fast-forward the game.
        var runs = 0
        while frameAccumulator >= coreInterval && runs < 4 {
            retro_run?()
            frameAccumulator -= coreInterval
            runs += 1
        }

        // Only drop the backlog when it is far beyond what pacing produces, and
        // even then keep the sub-frame remainder. Clearing it outright would leak
        // a slice of time on every busy tick and run the core permanently slow,
        // which is what pulled the audio out of sync.
        if frameAccumulator > coreInterval * 4 {
            frameAccumulator = frameAccumulator.truncatingRemainder(dividingBy: coreInterval)
        }

        countFrames(ran: runs)
    }

    // MARK: - Pacing diagnostics

    private var frameRateWindowStart: CFTimeInterval = 0
    private var frameRateWindowCount = 0

    /// Reports the rate the core actually achieves versus what it asked for. A
    /// gap here is the first thing to look at when audio drifts, since the core
    /// produces its samples per frame.
    private func countFrames(ran: Int) {
        frameRateWindowCount += ran
        let now = CACurrentMediaTime()
        if frameRateWindowStart == 0 {
            frameRateWindowStart = now
            return
        }
        let elapsed = now - frameRateWindowStart
        guard elapsed >= 3 else { return }
        let measured = Double(frameRateWindowCount) / elapsed
        print(String(
            format: "[Libretro] pacing: %.2f fps measured, %.2f expected, audio buffered %.0f ms",
            measured, coreFPS, audioBufferedMilliseconds()
        ))
        frameRateWindowStart = now
        frameRateWindowCount = 0
    }

    func stop() {
        guard handle != nil else { return }
        displayLink?.invalidate()
        displayLink = nil
        stopAudio()
        clearAllButtons()
        writeSRAMToDisk()
        sramURL = nil
        retro_unload_game?()
        retro_deinit?()
        if let h = handle {
            dlclose(h)
            handle = nil
        }
        // Drop stale C function pointers into the now-unmapped dylib so a
        // delayed pause/resume from a stray scenePhase callback can't jump
        // into freed text segments.
        retro_init = nil; retro_deinit = nil
        retro_get_system_info = nil; retro_get_system_av_info = nil
        retro_set_environment = nil; retro_set_video_refresh = nil
        retro_set_audio_sample = nil; retro_set_audio_sample_batch = nil
        retro_set_input_poll = nil; retro_set_input_state = nil
        retro_set_controller_port_device = nil
        retro_run = nil; retro_reset = nil
        retro_load_game = nil; retro_unload_game = nil
        retro_serialize_size = nil; retro_serialize = nil; retro_unserialize = nil
        retro_get_memory_data = nil; retro_get_memory_size = nil
    }

    func pause() {
        guard handle != nil else { return }
        guard let link = displayLink, !link.isPaused else { return }
        link.isPaused = true
        clearAllButtons()
        pauseAudio()
        writeSRAMToDisk()
    }

    func resume() {
        guard handle != nil else { return }
        resumeAudio()
        guard let link = displayLink, link.isPaused else { return }
        // Start from a clean slate: the time spent paused is not a backlog of
        // frames the core owes us.
        frameAccumulator = 0
        link.isPaused = false
    }

    // MARK: - Save / Load state

    func saveStateData() -> Data? {
        guard let sizeFn = retro_serialize_size, let serFn = retro_serialize else { return nil }
        let size = sizeFn()
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return serFn(base, size)
        }
        return ok ? data : nil
    }

    func loadStateData(_ data: Data) -> Bool {
        guard let unserFn = retro_unserialize else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return unserFn(base, data.count)
        }
    }

    // MARK: - Symbol resolution

    private func resolveSymbols() throws {
        retro_init                       = try sym("retro_init")
        retro_deinit                     = try sym("retro_deinit")
        retro_get_system_info            = try sym("retro_get_system_info")
        retro_get_system_av_info         = try sym("retro_get_system_av_info")
        retro_set_environment            = try sym("retro_set_environment")
        retro_set_video_refresh          = try sym("retro_set_video_refresh")
        retro_set_audio_sample           = try sym("retro_set_audio_sample")
        retro_set_audio_sample_batch     = try sym("retro_set_audio_sample_batch")
        retro_set_input_poll             = try sym("retro_set_input_poll")
        retro_set_input_state            = try sym("retro_set_input_state")
        retro_set_controller_port_device = try sym("retro_set_controller_port_device")
        retro_run                        = try sym("retro_run")
        retro_reset                      = try? sym("retro_reset")
        retro_load_game                  = try sym("retro_load_game")
        retro_unload_game                = try sym("retro_unload_game")
        retro_serialize_size             = try? sym("retro_serialize_size")
        retro_serialize                  = try? sym("retro_serialize")
        retro_unserialize                = try? sym("retro_unserialize")
        retro_get_memory_data            = try? sym("retro_get_memory_data")
        retro_get_memory_size            = try? sym("retro_get_memory_size")
    }

    private func sym<T>(_ name: String) throws -> T {
        guard let raw = dlsym(handle, name) else {
            throw FrontendError.symbolMissing(name)
        }
        return unsafeBitCast(raw, to: T.self)
    }
}
