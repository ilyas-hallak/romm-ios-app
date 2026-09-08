import Foundation

/// One configured emulator app's settings: where its saves are, and whether it
/// stays configured at all.
///
/// This is where the sync screen's folder controls moved to. Granting a folder
/// is a setup decision the user makes once, so it belongs beside the app it
/// concerns rather than beside a plan that only reads it.
@Observable
@MainActor
final class ExternalEmulatorAppSettingsViewModel {

    let emulator: ExternalEmulatorID

    private(set) var scan: ExternalSaveScan?
    private(set) var hasFolder = false
    private(set) var isInstalled = false
    var errorMessage: String?

    private let folderStore: PExternalSaveFolderStore
    private let setupStore: PExternalEmulatorSetupStore
    private let scanUseCase: PScanExternalSavesUseCase
    private let playTargetPreference: PPlayTargetPreference
    private let launcher: PExternalAppLauncher

    init(emulator: ExternalEmulatorID, factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.emulator = emulator
        self.folderStore = factory.externalSaveFolderStore
        self.setupStore = factory.externalEmulatorSetupStore
        self.scanUseCase = factory.makeScanExternalSavesUseCase()
        self.playTargetPreference = factory.playTargetPreference
        self.launcher = factory.externalAppLauncher
    }

    var displayName: String { emulator.emulator.displayName }

    /// False for an app whose save layout is unknown, which has no folder to
    /// point at and would otherwise offer a picker for nothing.
    var supportsSaveReading: Bool { emulator.emulator.saveLayout != nil }

    var isPlayTarget: Bool { playTargetPreference.current == .external(emulator) }

    func refresh() {
        isInstalled = launcher.isInstalled(emulator.emulator)
        hasFolder = folderStore.grantedFolder(for: emulator) != nil
        scan = hasFolder ? try? scanUseCase.execute(for: emulator) : nil
    }

    func grantFolder(_ url: URL) {
        do {
            try folderStore.remember(folderURL: url, for: emulator)
            refresh()
        } catch {
            errorMessage = String(
                localized: "Could not keep access to that folder: \(error.localizedDescription)"
            )
        }
    }

    func revokeFolder() {
        folderStore.forget(emulator)
        refresh()
    }

    /// Drops the app's setup entirely, folder included.
    ///
    /// Also clears the Play target when it pointed here: leaving it would send
    /// the next Play tap to an app the settings no longer list, which is the
    /// state that made removal impossible to reach in the first place.
    func removeApp() {
        folderStore.forget(emulator)
        setupStore.forget(emulator)
        if isPlayTarget {
            playTargetPreference.current = .builtIn
        }
        refresh()
    }
}
