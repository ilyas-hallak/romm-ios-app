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

    // MARK: - HW render readback
    /// Zielpuffer für `hwRenderReadbackCurrentFBO`. Bewusst manuell alloziert
    /// und über Frames hinweg wiederverwendet: der HW-Pfad läuft pro Frame,
    /// eine Allokation je Frame wäre reiner Ballast. Der Zeiger bleibt stabil,
    /// solange der Video-Sink daraus liest.
    private var hwReadbackStorage: UnsafeMutableRawPointer?
    private var hwReadbackCapacity: Int = 0

    /// Startgröße, falls `retro_get_system_av_info` keine brauchbare Geometrie
    /// liefert. Nur dafür da, dass überhaupt ein FBO existiert und der Core sein
    /// `context_reset` bekommt.
    private static let hwRenderFallbackSize: (Int32, Int32) = (640, 480)

    /// Liefert einen mindestens `byteCount` großen Puffer, ohne pro Frame neu
    /// zu allozieren.
    func hwReadbackBuffer(byteCount: Int) -> UnsafeMutableRawPointer? {
        guard byteCount > 0 else { return nil }
        if let buffer = hwReadbackStorage, hwReadbackCapacity >= byteCount {
            return buffer
        }
        hwReadbackStorage?.deallocate()
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 4)
        hwReadbackStorage = buffer
        hwReadbackCapacity = byteCount
        return buffer
    }

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

    // MARK: - Rumble state (port 0)

    /// Called whenever a motor level actually changes, with both channels
    /// normalized to 0...1.
    var onRumbleChanged: ((Float, Float) -> Void)?

    /// What the core last asked for.
    private var rumbleStrong: UInt16 = 0
    private var rumbleWeak: UInt16 = 0
    /// What we last handed to `onRumbleChanged`. Tracked separately from the core
    /// state so pausing can silence the motors without making the core's next
    /// (unchanged) value look like a no-op after resuming.
    private var reportedStrong: UInt16 = 0
    private var reportedWeak: UInt16 = 0

    /// Logged once, to tell "the core never calls" apart from "the core calls
    /// but only ever asks for zero".
    private var loggedFirstRumbleCall = false

    func setRumbleState(port: UInt32, effect: UInt32, strength: UInt16) {
        if !loggedFirstRumbleCall {
            loggedFirstRumbleCall = true
            print("[Libretro] first set_rumble_state: port=\(port) effect=\(effect) strength=\(strength)")
        }
        guard port == 0 else { return }
        switch effect {
        case LibretroABI.RUMBLE_STRONG: rumbleStrong = strength
        case LibretroABI.RUMBLE_WEAK: rumbleWeak = strength
        default: return
        }
        notifyRumbleIfChanged()
    }

    /// The core may call the rumble interface every frame, so only a real change
    /// is forwarded.
    private func notifyRumbleIfChanged() {
        guard rumbleStrong != reportedStrong || rumbleWeak != reportedWeak else { return }
        reportedStrong = rumbleStrong
        reportedWeak = rumbleWeak
        // A change is rare enough to log, unlike the per frame calls above.
        print("[Libretro] rumble strong=\(rumbleStrong) weak=\(rumbleWeak)")
        onRumbleChanged?(
            Float(rumbleStrong) / Float(UInt16.max),
            Float(rumbleWeak) / Float(UInt16.max)
        )
    }

    /// Silences the motors without touching the core state, so the next core
    /// value gets through again even if it is the one from before the pause.
    private func silenceRumble() {
        guard reportedStrong != 0 || reportedWeak != 0 else { return }
        reportedStrong = 0
        reportedWeak = 0
        onRumbleChanged?(0, 0)
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

    /// - Parameter portDevice: Device reported for controller port 0, usually
    ///   `LibretroABI.DEVICE_JOYPAD`. It is applied after `retro_load_game`,
    ///   which resets the port to a plain pad internally. No default here: the
    ///   constants are main-actor isolated, and a default argument is evaluated
    ///   in the caller's (nonisolated) context.
    func load(
        corePath: String,
        gamePath: String,
        systemDir: String,
        saveDir: String,
        portDevice: UInt32
    ) throws {
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

        // HW-Render-Pfad scharf schalten, bevor die Run-Loop startet. Reihenfolge
        // ist Vertrag: erst GL-Kontext, dann FBO, erst danach context_reset —
        // der Core legt darin seine GL-Ressourcen an und fragt sofort
        // get_current_framebuffer ab. Alles auf dem Main-Thread, auf dem auch
        // retro_run und der Readback laufen; ein EAGL-Kontext ist threadgebunden.
        if hwRenderIsActive() {
            let depth = hwRenderWantsDepth()
            let stencil = hwRenderWantsStencil()
            print("[Libretro] hw render: creating GLES3 context")
            if hwRenderMakeContext() {
                // Bewusst base_width/base_height: max_* ist Flycasts Obergrenze
                // für Upscaling, nicht die tatsächliche Framegröße.
                //
                // Notnagel gegen 0: meldet ein Core hier keine Geometrie, gäbe es
                // kein FBO und damit auch kein context_reset — der Core würde beim
                // ersten GL-Zugriff segfaulten. Lieber mit einer Startgröße
                // aufbauen; `hwRenderReadbackCurrentFBO` baut das FBO ohnehin neu,
                // sobald der erste echte Frame eine andere Größe meldet.
                var fbWidth = Int32(av.geometry.base_width)
                var fbHeight = Int32(av.geometry.base_height)
                if fbWidth <= 0 || fbHeight <= 0 {
                    print("[Libretro] hw render: Core meldet Geometrie \(fbWidth)x\(fbHeight) — Fallback auf \(Self.hwRenderFallbackSize.0)x\(Self.hwRenderFallbackSize.1)")
                    fbWidth = Self.hwRenderFallbackSize.0
                    fbHeight = Self.hwRenderFallbackSize.1
                }
                print("[Libretro] hw render: FBO \(fbWidth)x\(fbHeight) depth=\(depth) stencil=\(stencil) bottomLeftOrigin=\(hwRenderBottomLeftOrigin())")
                hwRenderSetupFramebufferEx(fbWidth, fbHeight, depth, stencil)
                hwRenderInvokeContextReset()
            } else {
                print("[Libretro] hw render: GLES3 context creation failed, core will render into nothing")
            }
        }

        retro_set_controller_port_device?(0, portDevice)

        startAudio(sampleRate: av.timing.sample_rate > 0 ? av.timing.sample_rate : 44100)
    }

    func startRunLoop() {
        frameAccumulator = 0
        #if DEBUG
        frameRateWindowStart = 0
        frameRateWindowCount = 0
        frameRateWindowThrottled = 0
        frameRateWindowFrameBase = frameCount
        #endif
        let driver = DisplayLinkDriver { [weak self] displayFrameDuration in
            MainActor.assumeIsolated {
                self?.stepEmulation(displayFrameDuration: displayFrameDuration)
            }
        }
        displayLink = driver
        driver.start()
    }

    private var coreFPS: Double {
        // Bounded, not just checked against zero: the core can rewrite the rate
        // at runtime and a bogus value would freeze or fast-forward the loop.
        (1...1000).contains(avInfo.timing.fps) ? avInfo.timing.fps : 60
    }

    /// Takes over the timings a core reports after loading. Flycast recomputes
    /// its frame rate from the SPG registers on every video mode change, so the
    /// value from `retro_get_system_av_info` is only the starting point.
    func applyAVInfo(_ info: LibretroABI.SystemAVInfo) {
        let previousFPS = avInfo.timing.fps
        avInfo = info
        if info.timing.fps != previousFPS {
            Logger.performance.info(String(
                format: "core retimed: %.4f Hz -> %.4f Hz", previousFPS, info.timing.fps
            ))
            // The backlog was measured against the old interval.
            frameAccumulator = 0
        }
        // Retuning would mean rebuilding the source node mid-frame. No core we
        // ship does this, so log it instead of carrying the machinery.
        if info.timing.sample_rate > 0, info.timing.sample_rate != Self.audioActiveSampleRate {
            Logger.general.notice("core changed sample rate to \(info.timing.sample_rate)Hz, engine stays at \(Self.audioActiveSampleRate)Hz")
        }
    }

    func applyGeometry(_ geometry: LibretroABI.GameGeometry) {
        avInfo.geometry = geometry
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
        var throttled = 0
        while frameAccumulator >= coreInterval && runs < 4 {
            // Debited before the check: a frame we skip is dropped, not owed.
            frameAccumulator -= coreInterval
            // The display clock only paces cores where one `retro_run` is exactly
            // one video frame of emulated time. PPSSPP and Flycast instead run
            // until the game presents, so a 30 Hz title advances two frames per
            // call and would run at double speed.
            guard !coreIsAheadOfAudio() else { throttled += 1; break }
            retro_run?()
            runs += 1
        }

        // Only drop the backlog when it is far beyond what pacing produces, and
        // even then keep the sub-frame remainder. Clearing it outright would leak
        // a slice of time on every busy tick and run the core permanently slow,
        // which is what pulled the audio out of sync.
        if frameAccumulator > coreInterval * 4 {
            frameAccumulator = frameAccumulator.truncatingRemainder(dividingBy: coreInterval)
        }

        #if DEBUG
        countFrames(ran: runs, throttled: throttled)
        #endif
    }

    #if DEBUG
    // MARK: - Pacing diagnostics

    private var frameRateWindowStart: CFTimeInterval = 0
    private var frameRateWindowCount = 0
    private var frameRateWindowThrottled = 0
    private var frameRateWindowFrameBase: UInt64 = 0

    /// Reports what the core achieves versus what it asked for.
    ///
    /// The three values exist to tell causes apart that otherwise look alike:
    /// `throttled` separates a core that cannot keep up (zero) from one held back
    /// by the audio clock; `runs` versus `video` shows cores that return zero or
    /// several frames per call; the audio rate is the only figure measuring
    /// emulated time rather than call counts.
    private func countFrames(ran: Int, throttled: Int) {
        frameRateWindowCount += ran
        frameRateWindowThrottled += throttled
        let now = CACurrentMediaTime()
        if frameRateWindowStart == 0 {
            frameRateWindowStart = now
            frameRateWindowFrameBase = frameCount
            return
        }
        let elapsed = now - frameRateWindowStart
        guard elapsed >= 1 else { return }
        let runs = Double(frameRateWindowCount) / elapsed
        let video = Double(frameCount - frameRateWindowFrameBase) / elapsed
        Logger.performance.debug(String(
            format: "pacing: %.2f runs/s, %.2f expected, %.2f video/s, %d throttled, audio buffered %.0f ms, underruns %d",
            runs, coreFPS, video, frameRateWindowThrottled, audioBufferedMilliseconds(), Self.audioUnderruns
        ))
        // Roughly the core's sample rate means real time, double means double
        // speed. A non-zero trim figure means the fill level is being held in
        // place and cannot be read as a speed signal.
        Logger.performance.debug(String(
            format: "audio rate: %.0f Hz from core, %.0f Hz expected, %.0f Hz trimmed away",
            Double(Self.audioFramesProduced) / elapsed,
            Self.audioActiveSampleRate,
            Double(Self.audioFramesTrimmed) / elapsed
        ))
        frameRateWindowStart = now
        frameRateWindowCount = 0
        frameRateWindowThrottled = 0
        frameRateWindowFrameBase = frameCount
        Self.audioFramesProduced = 0
        Self.audioFramesTrimmed = 0
    }
    #endif

    func stop() {
        guard handle != nil else { return }
        displayLink?.invalidate()
        displayLink = nil
        stopAudio()
        clearAllButtons()
        rumbleStrong = 0
        rumbleWeak = 0
        reportedStrong = 0
        reportedWeak = 0
        onRumbleChanged?(0, 0)
        writeSRAMToDisk()
        sramURL = nil
        retro_unload_game?()
        retro_deinit?()
        // Muss VOR dem dlclose laufen: der Teardown verwirft den gemerkten
        // context_reset/context_destroy des Cores, der sonst als Dangling
        // Pointer in die gleich entladene Dylib zeigen würde. Gibt zusätzlich
        // EAGL-Kontext und FBO frei, damit die nächste Session sauber startet.
        hwRenderTeardown()
        if let h = handle {
            dlclose(h)
            handle = nil
        }
        // Drop stale C function pointers into the now-unmapped dylib so a
        // delayed pause/resume from a stray scenePhase callback can't jump
        // into freed text segments. The rumble hook goes with them: the session
        // that owns its haptics is on its way out too.
        onRumbleChanged = nil
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
        silenceRumble()
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
