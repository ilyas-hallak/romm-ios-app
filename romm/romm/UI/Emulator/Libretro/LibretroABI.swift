import Foundation

/// Manuelle Spiegelung des libretro.h ABI – nur die Teile, die wir tatsächlich
/// brauchen. Quelle: libretro/libretro-common/libretro.h.
///
/// Mehr ergänzen, sobald ein Core ein nicht behandeltes Environment-Cmd anfragt.
enum LibretroABI {

    static let API_VERSION: UInt32 = 1

    // MARK: - Pixel formats
    enum PixelFormat: Int32 {
        case rgb1555 = 0   // 0RGB1555, native endian
        case xrgb8888 = 1  // XRGB8888, native endian
        case rgb565 = 2    // RGB565, native endian
    }

    // MARK: - Environment callback commands (subset)
    static let ENVIRONMENT_GET_OVERSCAN: UInt32 = 2
    static let ENVIRONMENT_GET_CAN_DUPE: UInt32 = 3
    static let ENVIRONMENT_SET_MESSAGE: UInt32 = 6
    static let ENVIRONMENT_SHUTDOWN: UInt32 = 7
    static let ENVIRONMENT_SET_PERFORMANCE_LEVEL: UInt32 = 8
    static let ENVIRONMENT_GET_SYSTEM_DIRECTORY: UInt32 = 9
    static let ENVIRONMENT_SET_PIXEL_FORMAT: UInt32 = 10
    static let ENVIRONMENT_SET_INPUT_DESCRIPTORS: UInt32 = 11
    static let ENVIRONMENT_GET_VARIABLE: UInt32 = 15
    static let ENVIRONMENT_SET_VARIABLES: UInt32 = 16
    static let ENVIRONMENT_GET_VARIABLE_UPDATE: UInt32 = 17
    static let ENVIRONMENT_GET_RUMBLE_INTERFACE: UInt32 = 23
    static let ENVIRONMENT_GET_LOG_INTERFACE: UInt32 = 27
    static let ENVIRONMENT_GET_SAVE_DIRECTORY: UInt32 = 31
    static let ENVIRONMENT_GET_INPUT_BITMASKS: UInt32 = 51 | 0x10000

    // MARK: - Memory types (retro_get_memory_data/size)
    static let MEMORY_SAVE_RAM: UInt32 = 0
    static let MEMORY_RTC: UInt32 = 1
    static let MEMORY_SYSTEM_RAM: UInt32 = 2
    static let MEMORY_VIDEO_RAM: UInt32 = 3

    // MARK: - Input devices
    static let DEVICE_NONE: UInt32 = 0
    static let DEVICE_JOYPAD: UInt32 = 1
    static let DEVICE_MOUSE: UInt32 = 2
    static let DEVICE_KEYBOARD: UInt32 = 3
    static let DEVICE_ANALOG: UInt32 = 5

    /// RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_ANALOG, 1), i.e. ((1 + 1) << 8) | 5 = 517.
    /// PCSX ReARMed only reports rumble while the port is set to DualShock.
    static let DEVICE_PSE_DUALSHOCK: UInt32 = 517

    // MARK: - Rumble effects
    static let RUMBLE_STRONG: UInt32 = 0
    static let RUMBLE_WEAK: UInt32 = 1

    // MARK: - Joypad buttons
    enum JoypadButton: UInt32 {
        case b = 0, y = 1, select = 2, start = 3
        case up = 4, down = 5, left = 6, right = 7
        case a = 8, x = 9, l = 10, r = 11
        case l2 = 12, r2 = 13, l3 = 14, r3 = 15
    }

    // MARK: - Structs (C-layout-kompatibel)
    struct SystemInfo {
        var library_name: UnsafePointer<CChar>?
        var library_version: UnsafePointer<CChar>?
        var valid_extensions: UnsafePointer<CChar>?
        var need_fullpath: Bool
        var block_extract: Bool
    }

    struct GameGeometry {
        var base_width: UInt32
        var base_height: UInt32
        var max_width: UInt32
        var max_height: UInt32
        var aspect_ratio: Float
    }

    struct SystemTiming {
        var fps: Double
        var sample_rate: Double
    }

    struct SystemAVInfo {
        var geometry: GameGeometry
        var timing: SystemTiming
    }

    struct GameInfo {
        var path: UnsafePointer<CChar>?
        var data: UnsafeRawPointer?
        var size: Int
        var meta: UnsafePointer<CChar>?
    }

    struct Variable {
        var key: UnsafePointer<CChar>?
        var value: UnsafePointer<CChar>?
    }

    /// retro_rumble_interface. The core only copies the function pointer out of
    /// this struct, so it may live on the stack.
    struct RumbleInterface {
        var set_rumble_state: SetRumbleStateFn?
    }

    // MARK: - Function pointer typedefs
    typealias EnvironmentFn = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool
    typealias VideoRefreshFn = @convention(c) (UnsafeRawPointer?, UInt32, UInt32, Int) -> Void
    typealias AudioSampleFn = @convention(c) (Int16, Int16) -> Void
    typealias AudioSampleBatchFn = @convention(c) (UnsafePointer<Int16>?, Int) -> Int
    typealias InputPollFn = @convention(c) () -> Void
    typealias InputStateFn = @convention(c) (UInt32, UInt32, UInt32, UInt32) -> Int16
    /// (port, effect, strength 0...0xffff) -> handled
    typealias SetRumbleStateFn = @convention(c) (UInt32, UInt32, UInt16) -> Bool

    typealias RetroInit = @convention(c) () -> Void
    typealias RetroDeinit = @convention(c) () -> Void
    typealias RetroAPIVersion = @convention(c) () -> UInt32
    typealias RetroGetSystemInfo = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias RetroGetSystemAVInfo = @convention(c) (UnsafeMutableRawPointer) -> Void
    typealias RetroSetEnvironment = @convention(c) (EnvironmentFn) -> Void
    typealias RetroSetVideoRefresh = @convention(c) (VideoRefreshFn) -> Void
    typealias RetroSetAudioSample = @convention(c) (AudioSampleFn) -> Void
    typealias RetroSetAudioSampleBatch = @convention(c) (AudioSampleBatchFn) -> Void
    typealias RetroSetInputPoll = @convention(c) (InputPollFn) -> Void
    typealias RetroSetInputState = @convention(c) (InputStateFn) -> Void
    typealias RetroSetControllerPortDevice = @convention(c) (UInt32, UInt32) -> Void
    typealias RetroReset = @convention(c) () -> Void
    typealias RetroRun = @convention(c) () -> Void
    typealias RetroSerializeSize = @convention(c) () -> Int
    typealias RetroSerialize = @convention(c) (UnsafeMutableRawPointer, Int) -> Bool
    typealias RetroUnserialize = @convention(c) (UnsafeRawPointer, Int) -> Bool
    typealias RetroLoadGame = @convention(c) (UnsafeRawPointer?) -> Bool
    typealias RetroUnloadGame = @convention(c) () -> Void
    typealias RetroGetMemoryData = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
    typealias RetroGetMemorySize = @convention(c) (UInt32) -> Int
}
