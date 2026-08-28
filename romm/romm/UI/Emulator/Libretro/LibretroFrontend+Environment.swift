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

        case LibretroABI.ENVIRONMENT_GET_SYSTEM_DIRECTORY:
            writeCString(systemDir, into: data)
            return true

        case LibretroABI.ENVIRONMENT_GET_SAVE_DIRECTORY:
            writeCString(saveDir, into: data)
            return true

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
            default: answer = nil
            }
            if let answer = answer {
                v.pointee.value = UnsafePointer(Self.cachedCString(answer))
                return true
            }
            v.pointee.value = nil
            return false

        case LibretroABI.ENVIRONMENT_SET_PERFORMANCE_LEVEL,
             LibretroABI.ENVIRONMENT_SET_VARIABLES,
             LibretroABI.ENVIRONMENT_SET_INPUT_DESCRIPTORS,
             LibretroABI.ENVIRONMENT_SET_MESSAGE:
            return true

        default:
            // print("[Libretro] unhandled env cmd: \(cmd)")
            return false
        }
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
