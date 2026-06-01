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

    private let getDownloadedROM: PGetDownloadedROMUseCase
    private let resolveROMFile: PResolveROMFileUseCase
    private let saveStates: PEmulatorSaveStatesUseCase
    private let biosSync: PBIOSSyncUseCase
    let aspectRatioPreference: PLibretroAspectRatioPreference
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
        factory: PDependencyFactory
    ) {
        self.rom = rom
        self.core = core
        self.getDownloadedROM = getDownloadedROM
        self.resolveROMFile = resolveROMFile
        self.saveStates = saveStates
        self.biosSync = biosSync
        self.aspectRatioPreference = aspectRatioPreference
        self.factory = factory
    }

    func bootstrap() {
        isLoading = true
        Task { @MainActor in
            let missing = await biosSync.missingMandatory(for: core)
            if !missing.isEmpty {
                let names = missing.map { $0.fileName }.joined(separator: ", ")
                errorMessage = "BIOS fehlt für \(core.displayName): \(names). In Einstellungen → BIOS Files herunterladen."
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
                cloudSync: cloudSync
            )
            s.onMenuRequested = { [weak self] in self?.onMenuRequested?() }
            session = s
            s.start()
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
