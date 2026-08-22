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

    /// Screen placement preference (drag-to-move + height). Set before `loadViewIfNeeded()`.
    var screenPositionPreference: PEmulatorScreenPositionPreference?

    /// Custom controller skin picked in Settings, or `nil` for the core's
    /// built-in one. Whether a skin can render depends on the current traits,
    /// which only exist once the view has a window and change on every
    /// rotation, so the decision is re-made on every skin pass rather than
    /// once at setup.
    var customControllerSkin: ControllerSkin?

    /// `verticalOffset` captured at the start of a drag, so the whole gesture is
    /// applied relative to it.
    private var basePanOffset: Double?

    /// Lets the user drag the game vertically. Only enabled while the on-screen
    /// controls are hidden (a physical controller is connected), so it never
    /// competes with the touch skin. Toggled from the session.
    private lazy var screenPanRecognizer: UIPanGestureRecognizer = {
        let r = UIPanGestureRecognizer(target: self, action: #selector(handleScreenPan(_:)))
        r.isEnabled = false
        return r
    }()

    /// Enable/disable drag-to-move from the session (mirrors control visibility).
    var isScreenDragEnabled: Bool {
        get { screenPanRecognizer.isEnabled }
        set { screenPanRecognizer.isEnabled = newValue }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addGestureRecognizer(screenPanRecognizer)
    }

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

    /// Whether the custom placement applies right now: only while a physical
    /// controller is connected (so a gamepad case doesn't cover the game),
    /// portrait, single-screen (dual-screen systems like DS keep the default).
    private var isCustomPlacementActive: Bool {
        guard view.bounds.height >= view.bounds.width else { return false }
        guard gameViews.count == 1 else { return false }
        return EmulatorControllerState.isConnected
    }

    /// Repositions the single game screen: limits its height to `heightFraction`
    /// of the safe area and slides it to `verticalOffset` (0 = top … 1 = bottom).
    private func applyCustomScreenPlacement() {
        guard let pref = screenPositionPreference else { return }
        guard isCustomPlacementActive, let gameView = gameViews.first else { return }

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

    /// Drag-to-move handler: converts the vertical pan into a `verticalOffset`
    /// (0…1) relative to where the drag started, then re-lays out so
    /// `applyCustomScreenPlacement()` slides the game live.
    @objc private func handleScreenPan(_ gesture: UIPanGestureRecognizer) {
        guard let pref = screenPositionPreference, isCustomPlacementActive,
              let gameView = gameViews.first else { return }

        switch gesture.state {
        case .began:
            basePanOffset = pref.verticalOffset
        case .changed:
            let availableHeight = view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom
            // Free travel = space not taken by the game; the height is fixed
            // during a vertical drag, so this stays stable across the gesture.
            let free = max(1, availableHeight - gameView.frame.height)
            let base = basePanOffset ?? pref.verticalOffset
            let delta = Double(gesture.translation(in: view).y / free)
            pref.verticalOffset = min(1.0, max(0.0, base + delta))
            view.setNeedsLayout()
        case .ended, .cancelled, .failed:
            basePanOffset = nil
        default:
            break
        }
    }

    /// Reassign the controller skin to rebuild `gameViews` for dual-screen
    /// systems (e.g. Nintendo DS). Setting `controllerSkin` posts the change
    /// notification that triggers `GameViewController.updateGameViews()`,
    /// which `updateControllerSkin()` alone does not do.
    ///
    /// This is also where a custom skin wins or loses: it is only kept while it
    /// can actually render for the current traits, otherwise we swap back to the
    /// core's built-in skin. A skin that only ships portrait artwork must not
    /// leave the player with an invisible overlay after rotating.
    private func reapplyControllerSkin() {
        guard let cv = controllerView else { return }
        guard let skin = resolvedControllerSkin(for: cv) else { return }
        cv.controllerSkin = skin
    }

    private func resolvedControllerSkin(for cv: ControllerView) -> ControllerSkinProtocol? {
        if let custom = customControllerSkin, canRender(custom, in: cv) { return custom }
        guard let gameType = game?.type,
              let standard = ControllerSkin.standardControllerSkin(for: gameType) else {
            // No standard skin to fall back to: keep whatever is loaded rather
            // than clearing the controls entirely.
            return cv.controllerSkin
        }
        return standard
    }

    /// A skin without artwork for the current traits renders as an invisible
    /// overlay, which would look like the controls simply vanished.
    private func canRender(_ skin: ControllerSkin, in cv: ControllerView) -> Bool {
        guard let traits = cv.controllerSkinTraits,
              let supported = skin.supportedTraits(for: traits) else { return false }
        return skin.image(for: supported, preferredSize: cv.controllerSkinSize ?? .medium) != nil
    }
}

@MainActor
final class NativeEmulatorSession: NSObject, GameViewControllerDelegate {

    private let gameURL: URL
    private let gameType: GameType
    private let saveStates: PEmulatorSaveStatesUseCase
    private let romId: Int
    private let cloudSync: CloudSaveSyncService?
    private let logger = Logger.ui
    let screenPositionPreference: PEmulatorScreenPositionPreference

    var onMenuRequested: (() -> Void)?
    /// Reports whether the on-screen touch controls are currently hidden, so the
    /// SwiftUI layer can show a standalone menu button in their place.
    var onControlsHiddenChanged: ((Bool) -> Void)?

    let viewController: GameViewController

    /// Owned here so the display manager can hold it weakly: the target must not
    /// outlive the core it renders from.
    private var externalRenderTarget: DeltaCoreExternalRenderTarget?

    // MARK: - GameViewControllerDelegate

    func gameViewController(_ gameViewController: GameViewController, handleMenuInputFrom gameController: GameController) {
        onMenuRequested?()
    }

    private var emulatorCore: EmulatorCore? {
        viewController.emulatorCore
    }

    init(gameURL: URL, gameType: GameType, romId: Int, saveStates: PEmulatorSaveStatesUseCase, screenPositionPreference: PEmulatorScreenPositionPreference, controllerSkinURL: URL? = nil, cloudSync: CloudSaveSyncService? = nil) {
        self.gameURL = gameURL
        self.gameType = gameType
        self.romId = romId
        self.saveStates = saveStates
        self.cloudSync = cloudSync
        self.screenPositionPreference = screenPositionPreference

        let vc = RommGameViewController()
        vc.screenPositionPreference = screenPositionPreference
        vc.loadViewIfNeeded()
        // Setting `game` makes DeltaCore run `prepareForGame()`, which installs
        // the core's built-in skin. A custom skin is handed to the view
        // controller instead of assigned here, so it survives that call and gets
        // re-validated against the current traits on every layout and rotation.
        vc.game = Game(fileURL: gameURL, type: gameType)
        vc.controllerView?.playerIndex = 0
        vc.customControllerSkin = Self.loadControllerSkin(at: controllerSkinURL, gameType: gameType)
        self.viewController = vc
        super.init()
        vc.delegate = self
    }

    /// Loads the `.deltaskin` at `url`, or returns `nil` to stay on the built-in
    /// skin. A skin the user imported for another system must never be applied,
    /// since its button layout wouldn't match the running core.
    private static func loadControllerSkin(at url: URL?, gameType: GameType) -> ControllerSkin? {
        guard let url else { return nil }
        guard let skin = ControllerSkin(fileURL: url) else {
            Logger.ui.warning("Controller skin \(url.lastPathComponent) failed to load, using the built-in skin")
            return nil
        }
        guard skin.gameType == gameType else {
            Logger.ui.warning("Controller skin \(url.lastPathComponent) is for \(skin.gameType.rawValue), not \(gameType.rawValue)")
            return nil
        }
        return skin
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
            // First: DeltaCore picks its output volume as the core comes up, and
            // would mute itself if another app still held the audio by then.
            EmulatorAudioSession.activate()
            self.viewController.startEmulation()
            // Assigning this re-runs that volume decision, now without the
            // ring switch muting a console the user deliberately started.
            self.emulatorCore?.audioManager.respectsSilentMode = false
            self.attachExternalControllers()
            self.observeControllerConnections()
            self.registerExternalRenderTarget()
            guard let slot = resumeSlot else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.viewController.pauseEmulation()
            do {
                try await self.loadState(slot: slot)
            } catch {
                self.logger.error("Resume from slot \(slot) failed: \(error.localizedDescription)")
            }
            self.viewController.resumeEmulation()
        }
    }

    func pause() { viewController.pauseEmulation() }
    func resume() {
        viewController.resumeEmulation()
        // Controller may have (dis)connected while paused in the menu.
        updateOnScreenControlsVisibility()
    }

    /// Re-apply the screen placement after the height changed in the menu.
    func refreshScreenPlacement() {
        viewController.view.setNeedsLayout()
    }

    func stop() {
        // Pause the render thread before flushing battery — DeltaCore expects
        // the emulator to be paused around save(), otherwise the save can race
        // with an in-flight frame and crash.
        viewController.pauseEmulation()
        flushBattery()
        detachExternalControllers()
        // Before `core.stop()`: the core must not be torn down while a view of
        // ours is still registered as one of its render targets.
        ExternalDisplayManager.shared.setRenderTarget(nil)
        externalRenderTarget = nil
        NotificationCenter.default.removeObserver(self)
        emulatorCore?.stop()
    }

    // MARK: - External display

    /// Registered once the core exists. Whether it actually paints is the display
    /// manager's call, so there is nothing to observe here.
    private func registerExternalRenderTarget() {
        guard let core = emulatorCore else { return }
        let target = DeltaCoreExternalRenderTarget(core: core)
        externalRenderTarget = target
        ExternalDisplayManager.shared.setRenderTarget(target)
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
        #if DEBUG
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(simulatedControllerChanged),
            name: .emulatorSimulatedControllerChanged,
            object: nil
        )
        #endif
    }

    #if DEBUG
    @objc private func simulatedControllerChanged() {
        updateOnScreenControlsVisibility()
        refreshScreenPlacement()
    }
    #endif

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
        let hide = shouldHideOnScreenControls
        viewController.controllerView?.isHidden = hide
        // Drag-to-move is only available when the touch skin is out of the way.
        (viewController as? RommGameViewController)?.isScreenDragEnabled = hide
        onControlsHiddenChanged?(hide)
    }

    /// Hide the on-screen buttons when a physical controller is connected — a
    /// standalone menu button takes over and the game becomes draggable.
    private var shouldHideOnScreenControls: Bool {
        EmulatorControllerState.isConnected
    }

    // MARK: - Save / Load

    func saveState(slot: Int) async throws {
        guard let core = emulatorCore else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-\(UUID().uuidString).dltastate")
        core.saveSaveState(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let data = try await settledStateData(at: tmp)
        // Rotate only once the new state is in hand, so a failed capture
        // cannot destroy what was already there.
        try saveStates.backupSlotForUndoSave(romId: romId, slot: slot)
        try saveStates.writeState(romId: romId, slot: slot, data: data)
        let thumb = currentThumbnailPNG()
        if let thumb {
            try saveStates.writeThumbnail(romId: romId, slot: slot, data: thumb)
        }
        cloudSync?.pushState(slot: slot, data: data, thumbnail: thumb)
    }

    func loadState(slot: Int) async throws {
        guard let core = emulatorCore else { return }
        guard let data = try saveStates.readState(romId: romId, slot: slot) else { return }
        try await captureUndoLoadSnapshot(core: core)
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

    private func captureUndoLoadSnapshot(core: EmulatorCore) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("undoload-\(UUID().uuidString).dltastate")
        core.saveSaveState(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let data = try await settledStateData(at: tmp)
        let thumb = currentThumbnailPNG()
        try saveStates.writeUndoLoadSnapshot(romId: romId, stateData: data, thumbnailData: thumb)
    }

    /// Mupen64Plus queues the gzip write on a worker thread and reports done
    /// before the bytes land, so wait for the file to stop growing.
    private func settledStateData(at url: URL) async throws -> Data {
        let pollInterval: UInt64 = 50_000_000
        let deadline = Date().addingTimeInterval(15)
        var previousSize: UInt64?

        while Date() < deadline {
            let size = fileSize(at: url)
            if let size, size > 0, size == previousSize {
                let data = try Data(contentsOf: url)
                // A write resuming mid-read would hand back another torso.
                if fileSize(at: url) == UInt64(data.count) { return data }
                previousSize = nil
            } else {
                previousSize = size
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }

        throw SaveStateCaptureError.incomplete
    }

    private func fileSize(at url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value
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
        // If the view disappears before startEmulation() runs, the core is still
        // .stopped and save() dereferences NULL (EXC_BAD_ACCESS in N64/GPGX).
        guard let core = emulatorCore, core.state != .stopped else { return }
        core.save()
        let savURL = Game(fileURL: gameURL, type: gameType).gameSaveURL
        if let data = try? Data(contentsOf: savURL) {
            try? saveStates.writeBattery(romId: romId, data: data)
            cloudSync?.pushBattery(data: data)
        }
    }
}
