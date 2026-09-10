import Foundation

enum EmulatorEngine: String, CaseIterable, Codable, Sendable {
    case web
    #if !APP_STORE
    case native
    #endif
    case auto
}

/// Runtime/compile feature switches.
enum AppFeatures {
    /// Server-hosted EmulatorJS (the `.web` engine) is available in local
    /// development (DEBUG) and in TestFlight builds, where we still test it, but
    /// is disabled in the real App Store release, there it does not work and
    /// would not pass App Review. On-device cores remain available in every
    /// build: DeltaCore outside the App Store build, libretro either way.
    ///
    /// This stays a runtime check on the receipt type rather than keying off
    /// `APP_STORE`, so a Release build of either target behaves the same when
    /// it is installed from TestFlight.
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
