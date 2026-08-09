import Foundation

enum EmulatorEngine: String, CaseIterable, Codable, Sendable {
    case web
    case native
    case auto
}

/// Runtime/compile feature switches.
enum AppFeatures {
    /// Server-hosted EmulatorJS (the `.web` engine) is available in local
    /// development (DEBUG) and in TestFlight builds, where we still test it, but
    /// is disabled in the real App Store release — there it does not work and
    /// would not pass App Review. Native on-device cores (DeltaCore / libretro)
    /// remain available in every build.
    ///
    /// TestFlight and App Store ship the *same* Release binary, so this cannot be
    /// a compile-time flag — it must be decided at runtime via the receipt type.
    static var webEmulatorEnabled: Bool {
        #if DEBUG
        return true
        #else
        return isTestFlightBuild
        #endif
    }

    /// True when running a TestFlight (sandbox receipt) build, false for a
    /// production App Store build. Debug builds from Xcode have no receipt.
    static var isTestFlightBuild: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}
