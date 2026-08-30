import Foundation
import Darwin

extension LibretroFrontend {

    // MARK: - Static C callbacks

    static let envCallback: LibretroABI.EnvironmentFn = { cmd, data in
        return MainActor.assumeIsolated { LibretroFrontend.shared.handleEnv(cmd: cmd, data: data) }
    }

    static let videoRefreshCallback: LibretroABI.VideoRefreshFn = { data, width, height, pitch in
        MainActor.assumeIsolated {
            let s = LibretroFrontend.shared
            s.frameCount &+= 1
            if s.frameCount <= 5 || s.frameCount % 60 == 0 {
                print("[Libretro] frame #\(s.frameCount) data=\(data != nil ? "ptr" : "nil") \(width)x\(height) pitch=\(pitch) fmt=\(s.pixelFormat)")
            }

            // RETRO_HW_FRAME_BUFFER_VALID ist (void*)-1, also gerade NICHT nil:
            // ungeprüft würde der Software-Blit diesen Zeiger dereferenzieren
            // und sofort crashen. Stattdessen das FBO zurücklesen.
            if data == LibretroABI.HW_FRAME_BUFFER_VALID {
                let w = Int(width)
                let h = Int(height)
                guard w > 0, h > 0,
                      let buffer = s.hwReadbackBuffer(byteCount: w * h * 4),
                      hwRenderReadbackCurrentFBO(buffer, Int32(w), Int32(h)) else {
                    return
                }
                s.videoSink?.libretroDidProduceFrame(
                    data: UnsafeRawPointer(buffer), width: width, height: height,
                    pitch: w * 4, pixelFormat: .rgba8888
                )
                return
            }

            s.videoSink?.libretroDidProduceFrame(
                data: data, width: width, height: height, pitch: pitch,
                pixelFormat: s.pixelFormat
            )
        }
    }

    static let audioSampleCallback: LibretroABI.AudioSampleFn = { left, right in
        var pair: [Int16] = [left, right]
        pair.withUnsafeBufferPointer { buf in
            MainActor.assumeIsolated {
                LibretroFrontend.shared.enqueueAudio(buf.baseAddress!, frames: 1)
            }
        }
    }

    static let audioBatchCallback: LibretroABI.AudioSampleBatchFn = { data, frames in
        guard let data = data else { return frames }
        MainActor.assumeIsolated {
            LibretroFrontend.shared.enqueueAudio(data, frames: frames)
        }
        return frames
    }

    static let inputPollCallback: LibretroABI.InputPollFn = { }

    static let inputStateCallback: LibretroABI.InputStateFn = { port, device, _, id in
        guard port == 0, device == LibretroABI.DEVICE_JOYPAD, id < 16 else { return 0 }
        return MainActor.assumeIsolated {
            LibretroFrontend.shared.buttonState[Int(id)] ? 1 : 0
        }
    }

    static let setRumbleStateCallback: LibretroABI.SetRumbleStateFn = { port, effect, strength in
        MainActor.assumeIsolated {
            LibretroFrontend.shared.setRumbleState(port: port, effect: effect, strength: strength)
        }
        return true
    }

    // MARK: - Environment dispatch

    func handleEnv(cmd: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
        switch cmd {
        case LibretroABI.ENVIRONMENT_GET_OVERSCAN, LibretroABI.ENVIRONMENT_GET_CAN_DUPE:
            data?.assumingMemoryBound(to: Bool.self).pointee = true
            return true

        case LibretroABI.ENVIRONMENT_SET_PIXEL_FORMAT:
            guard let raw = data?.assumingMemoryBound(to: Int32.self).pointee,
                  let pf = LibretroABI.PixelFormat(rawValue: raw) else { return false }
            self.pixelFormat = pf
            print("[Libretro] pixel format: \(pf)")
            return true

        case LibretroABI.ENVIRONMENT_SET_HW_RENDER:
            // Die retro_hw_render_callback-struct wird ausschliesslich in
            // ObjC++ gegen die echte libretro.h ausgewertet.
            guard hwRenderHandleSetHWRender(data) else { return false }
            // glReadPixels liefert RGBA in Speicherreihenfolge; die View muss
            // den Readback entsprechend interpretieren.
            self.pixelFormat = .rgba8888
            print("[Libretro] hw render accepted, pixel format forced to \(self.pixelFormat)")
            return true

        case LibretroABI.ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            writeCString(systemDir, into: data)
            return true

        case LibretroABI.ENVIRONMENT_GET_SAVE_DIRECTORY:
            writeCString(saveDir, into: data)
            return true

        case LibretroABI.ENVIRONMENT_GET_LOG_INTERFACE:
            // Ablehnen ist laut Spec erlaubt, aber PPSSPP prueft seinen log_cb
            // nicht gegen NULL und ruft ihn noch in retro_init auf — das killt
            // den Prozess. Siehe LibretroLog.h. Die struct wird in ObjC++
            // befuellt, weil retro_log_printf_t C-variadisch ist.
            return libretroInstallLogInterface(data)

        case LibretroABI.ENVIRONMENT_GET_VARIABLE_UPDATE:
            data?.assumingMemoryBound(to: Bool.self).pointee = false
            return true

        case LibretroABI.ENVIRONMENT_GET_RUMBLE_INTERFACE:
            guard let data = data else { return false }
            data.assumingMemoryBound(to: LibretroABI.RumbleInterface.self).pointee =
                LibretroABI.RumbleInterface(set_rumble_state: Self.setRumbleStateCallback)
            print("[Libretro] rumble interface handed to core")
            return true

        case LibretroABI.ENVIRONMENT_GET_VARIABLE:
            // pcsx_rearmed default `pcsx_rearmed_memcard1 = "disabled"` means the core
            // never allocates the SAVE_RAM buffer -- so retro_get_memory_size(0) returns
            // 0 and our .srm load/save is a silent no-op. Forcing "libretro" enables
            // the frontend-managed memory card path.
            guard let data = data else { return false }
            let v = data.assumingMemoryBound(to: LibretroABI.Variable.self)
            guard let keyPtr = v.pointee.key else { v.pointee.value = nil; return false }
            let key = String(cString: keyPtr)
            let answer: String?
            switch key {
            case "pcsx_rearmed_memcard1", "pcsx_rearmed_memcard2": answer = "libretro"
            // The core would otherwise swallow L1+R1+Select as its analog toggle,
            // which collides with our own L1+R1 menu shortcut. We do not support
            // analog sticks anyway, so a manual toggle buys nothing.
            case "pcsx_rearmed_analog_combo": answer = "disabled"
            // Flycast would otherwise render on its own thread, which has no
            // current EAGL context -- our context lives on the main thread that
            // drives retro_run. Threaded rendering there means no output at all.
            case "reicast_threaded_rendering": answer = "disabled"
            // PPSSPP defaults ppsspp_cpu_core to "JIT" (libretro_core_options.h:138).
            // iOS app processes have no JIT entitlement, and without an answer here
            // the core keeps the plain interpreter it presets in retro_load_game --
            // correct, but far slower than the IR interpreter. "IR JIT" is the option
            // VALUE that libretro.cpp:549 maps to CPUCore::IR_INTERPRETER; its label
            // reads "IR Interpreter".
            case "ppsspp_cpu_core": answer = "IR JIT"
            // Backend "auto" lets the core probe Vulkan (and finally software
            // rendering) whenever the GLES context is not taken. Pinning OpenGL keeps
            // it on the GLES2 path that our SET_HW_RENDER handler serves.
            case "ppsspp_backend": answer = "opengl"
            // Pflichtantwort, kein Tuning: retro_init setzt g_Config.iInternalResolution
            // hart auf 0 (libretro.cpp:1211) und nur check_variables schreibt hier einen
            // echten Wert. Ohne Antwort bleibt die 0 stehen, retro_get_system_av_info
            // meldet 0x0 (base = iInternalResolution * NATIVEWIDTH) und wir bauen kein
            // FBO -- der Core bekaeme nie context_reset und segfaultet beim GPU-Init.
            // "480x272" ist der Default des Cores (1x nativ) und halt den Readback klein.
            case "ppsspp_internal_resolution": answer = "480x272"
            // Der Grund fuer "laeuft zu schnell". PPSSPP beendet ein retro_run
            // nicht nach einem Vblank, sondern erst wenn __DisplayFlip
            // Core_NextFrame aufruft (sceDisplay.cpp:665). Das passiert per
            // Default nur, wenn der Framebuffer sich wirklich geaendert hat —
            // ein 30-fps-Titel emuliert also zwei Vblanks pro Aufruf, und bei
            // 60 Aufrufen/s laeuft er doppelt so schnell.
            // bRenderDuplicateFrames erzwingt den Flip bei JEDEM Vblank
            // (postEffectRequiresFlip, sceDisplay.cpp:615), womit ein retro_run
            // wieder genau ein Vblank ist.
            // Der Core bewirbt die Option mit Default "enabled"
            // (libretro_core_options.h:417), sein interner g_Config-Default ist
            // aber false (Config.cpp:758). Ohne Antwort gewinnt der interne
            // Default — die vierte Instanz desselben Musters wie bei
            // ppsspp_internal_resolution.
            case "ppsspp_frame_duplication": answer = "enabled"
            default: answer = nil
            }
            if let answer = answer {
                v.pointee.value = UnsafePointer(Self.cachedCString(answer))
                return true
            }
            v.pointee.value = nil
            return false

        case LibretroABI.ENVIRONMENT_SET_SYSTEM_AV_INFO:
            // Timing-relevant, nicht kosmetisch: Flycast rechnet die echte
            // Bildrate aus den SPG-Registern und meldet sie bei jedem
            // Videomodus-Wechsel nach (spg.cpp:67). Ohne Antwort pacen wir
            // ewig gegen die Rate, die beim Laden galt.
            guard let data = data else { return false }
            applyAVInfo(data.assumingMemoryBound(to: LibretroABI.SystemAVInfo.self).pointee)
            return true

        case LibretroABI.ENVIRONMENT_SET_GEOMETRY:
            // Nur Geometrie, die Timings bleiben stehen. PPSSPP reicht hier eine
            // ganze retro_system_av_info herein (libretro.cpp:1134) — die
            // beginnt mit der Geometrie, der Cast passt also fuer beide Cores.
            guard let data = data else { return false }
            applyGeometry(data.assumingMemoryBound(to: LibretroABI.GameGeometry.self).pointee)
            return true

        case LibretroABI.ENVIRONMENT_SET_PERFORMANCE_LEVEL,
             LibretroABI.ENVIRONMENT_SET_VARIABLES,
             LibretroABI.ENVIRONMENT_SET_INPUT_DESCRIPTORS,
             LibretroABI.ENVIRONMENT_SET_MESSAGE:
            return true

        default:
            logUnhandledEnv(cmd)
            return false
        }
    }

    /// Unbeantwortete Environment-Kommandos haben hier schon zweimal erst viel
    /// spaeter zugeschlagen (Absturz statt Fehlermeldung). Cores fragen manche
    /// davon pro Frame, deshalb jede ID nur einmal loggen.
    nonisolated(unsafe) private static var loggedUnhandledEnv: Set<UInt32> = []

    private func logUnhandledEnv(_ cmd: UInt32) {
        guard Self.loggedUnhandledEnv.insert(cmd).inserted else { return }
        // Das Experimental-Bit gehoert nicht zur Kommandonummer in libretro.h.
        let base = cmd & ~UInt32(0x10000)
        print("[Libretro] unhandled env cmd: \(cmd)\(base != cmd ? " (base \(base))" : "")")
    }

    // C-Strings ablegen, sodass libretro sie referenzieren kann.
    nonisolated(unsafe) static var cStringStorage: [String: UnsafeMutablePointer<CChar>] = [:]

    static func cachedCString(_ value: String) -> UnsafeMutablePointer<CChar> {
        if let existing = cStringStorage[value] { return existing }
        let ptr = strdup(value)!
        cStringStorage[value] = ptr
        return ptr
    }

    func writeCString(_ value: String, into data: UnsafeMutableRawPointer?) {
        guard let data = data else { return }
        let ptr = Self.cachedCString(value)
        data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee = UnsafePointer(ptr)
    }
}
