import Foundation
import Observation
import SwiftUI
import DeltaCore
import GBADeltaCore
import SNESDeltaCore
import GPGXDeltaCore
import NESDeltaCore
import GBCDeltaCore
import N64DeltaCore
import MelonDSDeltaCore

@Observable
@MainActor
final class NativeEmulatorViewModel {
    let rom: Rom
    let gameType: DeltaGameType
    var errorMessage: String?
    var session: NativeEmulatorSession?
    var isLoading: Bool = true
    /// True when the on-screen touch controls are hidden (physical controller or
    /// Controller Mode "On") — the view shows a standalone menu button instead.
    var controlsHidden: Bool = false

    private let getDownloadedROM: PGetDownloadedROMUseCase
    private let resolveROMFile: PResolveROMFileUseCase
    private let saveStates: PEmulatorSaveStatesUseCase
    private let factory: PDependencyFactory
    private let logger = Logger.viewModel

    init(
        rom: Rom,
        gameType: DeltaGameType,
        getDownloadedROM: PGetDownloadedROMUseCase,
        resolveROMFile: PResolveROMFileUseCase,
        saveStates: PEmulatorSaveStatesUseCase,
        factory: PDependencyFactory
    ) {
        self.rom = rom
        self.gameType = gameType
        self.getDownloadedROM = getDownloadedROM
        self.resolveROMFile = resolveROMFile
        self.saveStates = saveStates
        self.factory = factory
    }

    /// The same instance the session is handed, so the in-game menu writes the
    /// swap where the session reads it back from.
    var gamepadFaceButtonPreference: PGamepadFaceButtonPreference { factory.gamepadFaceButtonPreference }

    /// Same idea for the menu shortcut: the in-game menu writes it where the
    /// session's input bridge reads it back from.
    var emulatorMenuShortcutPreference: PEmulatorMenuShortcutPreference { factory.emulatorMenuShortcutPreference }

    /// Save-state slot to auto-load once the core is running (chosen in the
    /// pre-launch sheet), or `nil` for a fresh start.
    private var resumeSlot: Int?

    func bootstrap(resumeSlot: Int? = nil) {
        self.resumeSlot = resumeSlot
        isLoading = true
        do {
            let resolved = try getDownloadedROM.execute(romId: rom.id)
            let url = try resolveROMFile.execute(rom: resolved.rom, baseURL: resolved.baseURL, gameType: gameType)
            let exists = FileManager.default.fileExists(atPath: url.path)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
            print("[NativeEmulatorVM] ROM url=\(url.path) exists=\(exists) size=\(size)")
            if !exists {
                let dirContents = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path))?.joined(separator: ", ") ?? "dir not found"
                errorMessage = "ROM file not found: \(url.lastPathComponent)\nExpected path: \(url.deletingLastPathComponent().lastPathComponent)/\nDir contents: \(dirContents)"
                isLoading = false
                return
            }
            let deltaType = Self.deltaCoreGameType(for: gameType)
            let batteryFileName = url.deletingPathExtension().lastPathComponent + ".sav"
            let cloudSync = factory.makeCloudSaveSyncService(
                romId: rom.id,
                emulator: "delta-ios",
                batteryFileName: batteryFileName
            )
            let skinURL = factory.makeControllerSkinsUseCase()
                .selectedSkinFileURL(forGameType: gameType.gameTypeIdentifier)
            session = NativeEmulatorSession(
                gameURL: url, gameType: deltaType,
                romId: rom.id, saveStates: saveStates,
                screenPositionPreference: factory.emulatorScreenPositionPreference,
                controllerSkinURL: skinURL,
                faceButtonPreference: factory.gamepadFaceButtonPreference,
                menuShortcutPreference: factory.emulatorMenuShortcutPreference,
                cloudSync: cloudSync
            )
            session?.onControlsHiddenChanged = { [weak self] hidden in
                self?.controlsHidden = hidden
            }
            // The session sequences the resume-load after emulation is live and
            // performs it while paused (see NativeEmulatorSession.start).
            session?.start(resumeSlot: resumeSlot)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation(.easeOut(duration: 0.3)) {
                    isLoading = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Native emulator launch failed: \(error)")
            isLoading = false
        }
    }

    func teardown() {
        session?.stop()
        session = nil
    }

    private static func deltaCoreGameType(for type: DeltaGameType) -> GameType {
        switch type {
        case .gba: return GBA.core.gameType
        case .snes: return SNES.core.gameType
        case .genesis: return GPGX.core.gameType
        case .nes: return NES.core.gameType
        case .gbc: return GBC.core.gameType
        case .n64: return N64.core.gameType
        case .ds: return MelonDS.core.gameType
        }
    }
}
