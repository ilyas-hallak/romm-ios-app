import UIKit

final class UIExternalAppLauncher: PExternalAppLauncher {

    @MainActor
    func isInstalled(_ emulator: ExternalEmulator) -> Bool {
        guard let url = emulator.probeURL else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    @MainActor
    func launch(_ emulator: ExternalEmulator, fileName: String) async -> Bool {
        guard let url = emulator.launchURL(fileName: fileName) else { return false }
        return await UIApplication.shared.open(url)
    }
}
