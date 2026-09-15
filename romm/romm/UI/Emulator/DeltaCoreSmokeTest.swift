#if !APP_STORE
import DeltaCore
import GBADeltaCore

enum DeltaCoreSmokeTest {
    static func ping() -> String {
        return "DeltaCore loaded. GBA gameType: \(GBA.core.gameType.rawValue)"
    }
}
#endif
