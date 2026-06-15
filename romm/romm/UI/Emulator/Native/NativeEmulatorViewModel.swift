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

    func bootstrap() {
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
            session = NativeEmulatorSession(
                gameURL: url, gameType: deltaType,
                romId: rom.id, saveStates: saveStates,
                cloudSync: cloudSync
            )
            session?.start()
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
