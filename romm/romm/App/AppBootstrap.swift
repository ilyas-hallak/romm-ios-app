import Foundation
#if DELTA_CORES
import DeltaCore
import GBADeltaCore
import SNESDeltaCore
import GPGXDeltaCore
import NESDeltaCore
import GBCDeltaCore
import N64DeltaCore
import MelonDSDeltaCore
#endif

enum AppBootstrap {
    static func run() {
        unbufferStandardOutput()
        #if DELTA_CORES
        registerNativeCores()
        // DeltaCore's own MFi/keyboard controller tracking, which
        // NativeEmulatorSession reads from. The libretro engine tracks
        // controllers itself (see EmulatorControllerState), so this has
        // nothing to warm up without Delta cores.
        ExternalGameControllerManager.shared.startMonitoring()
        #endif
    }

    /// `print()` schreibt nach stdout, und stdout ist an einer Pipe (etwa
    /// `devicectl --console`) blockgepuffert. Bei einem SIGKILL geht der Puffer
    /// verloren, sodass das Log genau vor der interessanten Zeile abbricht und
    /// den Absturz an der falschen Stelle vermuten laesst. Ungepuffert kostet
    /// pro Zeile einen write(2) — im Debug-Build der richtige Tausch.
    private static func unbufferStandardOutput() {
        #if DEBUG
        setvbuf(stdout, nil, _IONBF, 0)
        #endif
    }

    #if DELTA_CORES
    private static func registerNativeCores() {
        Delta.register(GBA.core)
        Delta.register(SNES.core)
        Delta.register(GPGX.core)
        Delta.register(NES.core)
        Delta.register(GBC.core)
        Delta.register(N64.core)
        Delta.register(MelonDS.core)
    }
    #endif
}
