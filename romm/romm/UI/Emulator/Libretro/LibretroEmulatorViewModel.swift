import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class LibretroEmulatorViewModel {
    let rom: Rom
    let core: LibretroCore
    var errorMessage: String?
    var session: LibretroSession?
    var isLoading: Bool = true
    var onMenuRequested: (() -> Void)?
    /// True when the on-screen touch controls are hidden (physical controller or
    /// Controller Mode "On") — the view shows a standalone menu button instead.
    var controlsHidden: Bool = false

    private let getDownloadedROM: PGetDownloadedROMUseCase
    private let resolveROMFile: PResolveROMFileUseCase
    private let saveStates: PEmulatorSaveStatesUseCase
    private let biosSync: PBIOSSyncUseCase
    let aspectRatioPreference: PLibretroAspectRatioPreference
    let screenPositionPreference: PEmulatorScreenPositionPreference
    private let menuShortcutPreference: PEmulatorMenuShortcutPreference?
    private let factory: PDependencyFactory
    private let logger = Logger.viewModel

    init(
        rom: Rom,
        core: LibretroCore,
        getDownloadedROM: PGetDownloadedROMUseCase,
        resolveROMFile: PResolveROMFileUseCase,
        saveStates: PEmulatorSaveStatesUseCase,
        biosSync: PBIOSSyncUseCase,
        aspectRatioPreference: PLibretroAspectRatioPreference,
        screenPositionPreference: PEmulatorScreenPositionPreference,
        menuShortcutPreference: PEmulatorMenuShortcutPreference? = nil,
        factory: PDependencyFactory
    ) {
        self.rom = rom
        self.core = core
        self.getDownloadedROM = getDownloadedROM
        self.resolveROMFile = resolveROMFile
        self.saveStates = saveStates
        self.biosSync = biosSync
        self.aspectRatioPreference = aspectRatioPreference
        self.screenPositionPreference = screenPositionPreference
        self.menuShortcutPreference = menuShortcutPreference
        self.factory = factory
    }

    /// Save-state slot to auto-load once the core is running (chosen in the
    /// pre-launch sheet), or `nil` for a fresh start.
    private var resumeSlot: Int?

    func bootstrap(resumeSlot: Int? = nil) {
        self.resumeSlot = resumeSlot
        isLoading = true
        Task { @MainActor in
            let missing = await biosSync.missingMandatory(for: core)
            if !missing.isEmpty {
                let names = missing.map { $0.fileName }.joined(separator: ", ")
                errorMessage = String(localized: "Required BIOS files are missing for \(core.displayName): \(names). Download them in Settings → BIOS Files.")
                isLoading = false
                return
            }
            self.bootstrapAfterBIOSCheck()
        }
    }

    private func bootstrapAfterBIOSCheck() {
        do {
            let resolved = try getDownloadedROM.execute(romId: rom.id)
            let url = try resolveROMFile.execute(
                rom: resolved.rom,
                baseURL: resolved.baseURL,
                allowedExtensions: core.allowedExtensions
            )
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("[LibretroVM] ROM url=\(url.path) exists=\(exists)")
            if !exists {
                errorMessage = "ROM file not found: \(url.lastPathComponent)"
                isLoading = false
                return
            }
            let batteryFileName = url.deletingPathExtension().lastPathComponent + ".srm"
            let cloudSync = factory.makeCloudSaveSyncService(
                romId: rom.id,
                emulator: "libretro-\(core.dylibName)",
                batteryFileName: batteryFileName
            )
            let s = LibretroSession(
                gameURL: url,
                core: core,
                romId: rom.id,
                saveStates: saveStates,
                aspectRatioPreference: aspectRatioPreference,
                screenPositionPreference: screenPositionPreference,
                menuShortcutPreference: menuShortcutPreference,
                faceButtonPreference: factory.gamepadFaceButtonPreference,
                cloudSync: cloudSync
            )
            s.onMenuRequested = { [weak self] in self?.onMenuRequested?() }
            s.onControlsHiddenChanged = { [weak self] hidden in self?.controlsHidden = hidden }
            session = s
            // The session sequences the resume-load after the core is up and
            // performs it while paused (see LibretroSession.start).
            s.start(resumeSlot: resumeSlot)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeOut(duration: 0.3)) {
                    isLoading = false
                }
            }
        } catch {
            errorMessage = "Could not open ROM file: \(error.localizedDescription)"
            logger.error("Libretro launch failed: \(error)")
            isLoading = false
        }
    }

    func teardown() {
        session?.stop()
        session = nil
    }
}
