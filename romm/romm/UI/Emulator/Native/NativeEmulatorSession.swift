import Foundation
import UIKit
import AVFoundation
import DeltaCore
import GBADeltaCore
import GameController

/// GameViewController subclass that forces the on-screen controller skin to
/// reload after a rotation. DeltaCore only loads the skin image on initial
/// layout, so without this the portrait skin stays active in landscape and the
/// controller renders as a centered portrait-aspect block.
final class RommGameViewController: GameViewController {
    private var didApplyInitialSkin = false

    /// "Controller Mode" placement preference. Set before `loadViewIfNeeded()`.
    var screenPositionPreference: PEmulatorScreenPositionPreference?

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.reapplyControllerSkin()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // DeltaCore has just positioned `gameViews`; nudge them to the user's
        // custom placement before the frame is committed.
        applyCustomScreenPlacement()
        guard !didApplyInitialSkin,
              view.window != nil,
              view.bounds.width > 0, view.bounds.height > 0 else { return }
        didApplyInitialSkin = true
        reapplyControllerSkin()
    }

    /// Repositions the single game screen per the Controller Mode preference:
    /// limits its height to `heightFraction` of the safe area and slides it to
    /// `verticalOffset` (0 = top … 1 = bottom). Portrait + single-screen only
    /// (dual-screen systems like DS keep DeltaCore's default layout).
    private func applyCustomScreenPlacement() {
        guard let pref = screenPositionPreference else { return }
        // Portrait only — landscape already fills the height.
        guard view.bounds.height >= view.bounds.width else { return }
        guard gameViews.count == 1, let gameView = gameViews.first else { return }

        let active: Bool
        switch pref.mode {
        case .off:    active = false
        case .always: active = true
        case .auto:   active = !GCController.controllers().isEmpty
        }
        guard active else { return }

        let current = gameView.frame
        guard current.width > 0, current.height > 0 else { return }

        let insets = view.safeAreaInsets
        let availableTop = insets.top
        let availableHeight = view.bounds.height - insets.top - insets.bottom
        guard availableHeight > 0 else { return }

        let fraction = CGFloat(min(1.0, max(0.3, pref.heightFraction)))
        let offset = CGFloat(min(1.0, max(0.0, pref.verticalOffset)))

        // Fit the game (keeping its aspect ratio) into a box that is at most
        // `fraction` of the available height and the full width.
        let box = CGRect(x: 0, y: 0, width: view.bounds.width, height: availableHeight * fraction)
        let fitted = AVMakeRect(aspectRatio: current.size, insideRect: box)

        let x = ((view.bounds.width - fitted.width) / 2).rounded()
        let free = max(0, availableHeight - fitted.height)
        let y = (availableTop + offset * free).rounded()
        gameView.frame = CGRect(x: x, y: y, width: fitted.width.rounded(), height: fitted.height.rounded())
    }

    /// Reassign the controller skin to rebuild `gameViews` for dual-screen
    /// systems (e.g. Nintendo DS). Setting `controllerSkin` posts the change
    /// notification that triggers `GameViewController.updateGameViews()`,
    /// which `updateControllerSkin()` alone does not do.
    private func reapplyControllerSkin() {
        guard let cv = controllerView, let skin = cv.controllerSkin else { return }
        cv.controllerSkin = skin
    }
}

@MainActor
final class NativeEmulatorSession: NSObject, GameViewControllerDelegate {

    private let gameURL: URL
    private let gameType: GameType
    private let saveStates: PEmulatorSaveStatesUseCase
    private let romId: Int
    private let cloudSync: CloudSaveSyncService?

    var onMenuRequested: (() -> Void)?

    let viewController: GameViewController

    // MARK: - GameViewControllerDelegate

    func gameViewController(_ gameViewController: GameViewController, handleMenuInputFrom gameController: GameController) {
        onMenuRequested?()
    }

    private var emulatorCore: EmulatorCore? {
        viewController.emulatorCore
    }

    init(gameURL: URL, gameType: GameType, romId: Int, saveStates: PEmulatorSaveStatesUseCase, screenPositionPreference: PEmulatorScreenPositionPreference, cloudSync: CloudSaveSyncService? = nil) {
        self.gameURL = gameURL
        self.gameType = gameType
        self.romId = romId
        self.saveStates = saveStates
        self.cloudSync = cloudSync

        let vc = RommGameViewController()
        vc.screenPositionPreference = screenPositionPreference
        vc.loadViewIfNeeded()
        let game = Game(fileURL: gameURL, type: gameType)
        vc.game = game
        vc.controllerView?.playerIndex = 0
        self.viewController = vc
        super.init()
        vc.delegate = self
    }

    // MARK: - Slot info

    func hasState(slot: Int) -> Bool {
        (try? saveStates.readState(romId: romId, slot: slot)) != nil
    }

    func stateModifiedAt(slot: Int) -> Date? {
        saveStates.stateModifiedAt(romId: romId, slot: slot)
    }

    func thumbnail(slot: Int) -> UIImage? {
        guard let data = try? saveStates.readThumbnail(romId: romId, slot: slot) else { return nil }
        return UIImage(data: data)
    }

    func hasUndoSave(slot: Int) -> Bool { saveStates.hasUndoSave(romId: romId, slot: slot) }
    func hasUndoLoad() -> Bool { saveStates.hasUndoLoad(romId: romId) }

    func undoLoadThumbnail() -> UIImage? {
        guard let data = try? saveStates.readUndoLoadThumbnail(romId: romId) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Lifecycle

    /// - Parameter resumeSlot: Save-state slot to auto-load once emulation is
    ///   live, or `nil` to start fresh. Sequenced after `startEmulation()` and
    ///   loaded while paused, mirroring the in-game menu's load path.
    func start(resumeSlot: Int? = nil) {
        Task { [weak self] in
            guard let self else { return }
            await self.cloudSync?.pullBeforeLaunch()
            self.loadBatteryIfAvailable()
            self.viewController.startEmulation()
            self.attachExternalControllers()
            self.observeControllerConnections()
            guard let slot = resumeSlot else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.viewController.pauseEmulation()
            do {
                try self.loadState(slot: slot)
            } catch {
                print("[Native] resume from slot \(slot) failed: \(error.localizedDescription)")
            }
            self.viewController.resumeEmulation()
        }
    }

    func pause() { viewController.pauseEmulation() }
    func resume() { viewController.resumeEmulation() }

    func stop() {
        // Pause the render thread before flushing battery — DeltaCore expects
        // the emulator to be paused around save(), otherwise the save can race
        // with an in-flight frame and crash.
        viewController.pauseEmulation()
        flushBattery()
        detachExternalControllers()
        NotificationCenter.default.removeObserver(self)
        emulatorCore?.stop()
    }

    // MARK: - External Controllers

    private func attachExternalControllers() {
        guard let core = emulatorCore else { return }
        var nextIndex = 0
        for controller in ExternalGameControllerManager.shared.connectedControllers {
            controller.playerIndex = nextIndex
            controller.addReceiver(core)
            controller.addReceiver(viewController)
            nextIndex += 1
        }
        updateOnScreenControlsVisibility()
    }

    private func detachExternalControllers() {
        guard let core = emulatorCore else { return }
        for controller in ExternalGameControllerManager.shared.connectedControllers {
            controller.removeReceiver(core)
            controller.removeReceiver(viewController)
        }
    }

    private func observeControllerConnections() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalControllerDidConnect(_:)),
            name: .externalGameControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalControllerDidDisconnect(_:)),
            name: .externalGameControllerDidDisconnect,
            object: nil
        )
    }

    @objc private func externalControllerDidConnect(_ notification: Notification) {
        guard let controller = notification.object as? GameController,
              let core = emulatorCore else { return }
        let usedIndexes = Set(ExternalGameControllerManager.shared.connectedControllers.compactMap { $0.playerIndex })
        var nextIndex = 0
        while usedIndexes.contains(nextIndex) { nextIndex += 1 }
        controller.playerIndex = nextIndex
        controller.addReceiver(core)
        controller.addReceiver(viewController)
        updateOnScreenControlsVisibility()
    }

    @objc private func externalControllerDidDisconnect(_ notification: Notification) {
        guard let controller = notification.object as? GameController,
              let core = emulatorCore else { return }
        controller.removeReceiver(core)
        controller.removeReceiver(viewController)
        updateOnScreenControlsVisibility()
    }

    private func updateOnScreenControlsVisibility() {
        let hasExternal = !ExternalGameControllerManager.shared.connectedControllers.isEmpty
        viewController.controllerView?.isHidden = hasExternal
    }

    // MARK: - Save / Load

    func saveState(slot: Int) throws {
        guard let core = emulatorCore else { return }
        try saveStates.backupSlotForUndoSave(romId: romId, slot: slot)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-\(UUID().uuidString).dltastate")
        core.saveSaveState(to: tmp)
        let data = try Data(contentsOf: tmp)
        try saveStates.writeState(romId: romId, slot: slot, data: data)
        let thumb = currentThumbnailPNG()
        if let thumb {
            try saveStates.writeThumbnail(romId: romId, slot: slot, data: thumb)
        }
        try? FileManager.default.removeItem(at: tmp)
        cloudSync?.pushState(slot: slot, data: data, thumbnail: thumb)
    }

    func loadState(slot: Int) throws {
        guard let core = emulatorCore else { return }
        guard let data = try saveStates.readState(romId: romId, slot: slot) else { return }
        try captureUndoLoadSnapshot(core: core)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-\(UUID().uuidString).dltastate")
        try data.write(to: tmp)
        try core.load(SaveState(fileURL: tmp, gameType: gameType))
        try? FileManager.default.removeItem(at: tmp)
    }

    func undoSave(slot: Int) throws {
        _ = try saveStates.restoreSlotFromUndoSave(romId: romId, slot: slot)
    }

    func undoLoad() throws {
        guard let core = emulatorCore else { return }
        guard let data = try saveStates.readUndoLoadState(romId: romId) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-\(UUID().uuidString).dltastate")
        try data.write(to: tmp)
        try core.load(SaveState(fileURL: tmp, gameType: gameType))
        try? FileManager.default.removeItem(at: tmp)
        try saveStates.clearUndoLoad(romId: romId)
    }

    // MARK: - Helpers

    private func currentThumbnailPNG() -> Data? {
        guard let image = emulatorCore?.videoManager.snapshot() else { return nil }
        return image.pngData()
    }

    private func captureUndoLoadSnapshot(core: EmulatorCore) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("undoload-\(UUID().uuidString).dltastate")
        core.saveSaveState(to: tmp)
        let data = try Data(contentsOf: tmp)
        let thumb = currentThumbnailPNG()
        try saveStates.writeUndoLoadSnapshot(romId: romId, stateData: data, thumbnailData: thumb)
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - Battery

    private func loadBatteryIfAvailable() {
        guard let raw = try? saveStates.readBattery(romId: romId) else { return }
        let data = adaptBatteryForCore(raw: raw)
        let savURL = Game(fileURL: gameURL, type: gameType).gameSaveURL
        try? data.write(to: savURL, options: .atomic)
    }

    /// VBA-M (`CPUReadBatteryFile`) routes the .sav purely by file size:
    /// 0x20000 → Flash 128K, 0x10000 → Flash 64K, 0x8000 → SRAM, 0x2000/0x200
    /// → EEPROM. RomM/RetroArch-Saves are usually padded to 128KB regardless
    /// of cart type, so a 128KB blob is always loaded into the Flash region —
    /// which is the wrong memory for SRAM/EEPROM carts. We sniff the ROM for
    /// the standard "SRAM_", "EEPROM_", "FLASH…_" markers and trim the blob
    /// down (or pad up) to the size VBA-M will recognize for this cart.
    private func adaptBatteryForCore(raw: Data) -> Data {
        guard gameType == .gba else { return raw }
        guard let expected = expectedGBASaveSize() else { return raw }
        if raw.count == expected { return raw }
        if raw.count > expected {
            return raw.prefix(expected)
        }
        var padded = raw
        padded.append(Data(repeating: 0xFF, count: expected - raw.count))
        return padded
    }

    /// Returns the file size VBA-M's `CPUReadBatteryFile` expects for the
    /// current ROM's cart type, or `nil` if the ROM can't be inspected.
    private func expectedGBASaveSize() -> Int? {
        guard let rom = try? Data(contentsOf: gameURL, options: .mappedIfSafe) else { return nil }
        let markers: [(String, Int)] = [
            ("FLASH1M_", 0x20000),
            ("FLASH512_", 0x10000),
            ("EEPROM_", 0x2000),
            ("SRAM_", 0x8000),
            ("FLASH", 0x10000)
        ]
        for (needle, size) in markers {
            if rom.range(of: Data(needle.utf8)) != nil {
                return size
            }
        }
        return nil
    }

    private func flushBattery() {
        emulatorCore?.save()
        let savURL = Game(fileURL: gameURL, type: gameType).gameSaveURL
        if let data = try? Data(contentsOf: savURL) {
            try? saveStates.writeBattery(romId: romId, data: data)
            cloudSync?.pushBattery(data: data)
        }
    }
}
