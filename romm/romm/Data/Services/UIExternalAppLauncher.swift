import UIKit

final class UIExternalAppLauncher: PExternalAppLauncher {

    @MainActor
    func isInstalled(_ emulator: any PExternalEmulator) -> Bool {
        guard let url = emulator.probeURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    @MainActor
    func launch(_ emulator: any PExternalEmulator, gameIdentifier: String) async -> Bool {
        guard let url = emulator.launchURL(gameIdentifier: gameIdentifier) else { return false }
        return await UIApplication.shared.open(url)
    }
}
