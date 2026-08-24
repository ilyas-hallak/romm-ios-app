import Foundation

/// Opens external emulator apps, so view models can stay free of UIKit.
protocol PExternalAppLauncher: AnyObject {
    /// Whether the app is installed. Requires its scheme in `LSApplicationQueriesSchemes`.
    @MainActor func isInstalled(_ emulator: any PExternalEmulator) -> Bool
    /// Boots a ROM the app has already imported. False when the app refused the link.
    @MainActor func launch(_ emulator: any PExternalEmulator, gameIdentifier: String) async -> Bool
}
