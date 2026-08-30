import Foundation
import UIKit
import GameController

@MainActor
final class LibretroSession: NSObject {

    private let gameURL: URL
    private let core: LibretroCore
    private let romId: Int
    private let saveStates: PEmulatorSaveStatesUseCase
    private let aspectRatioPreference: PLibretroAspectRatioPreference
    let screenPositionPreference: PEmulatorScreenPositionPreference
    private let rumblePreference: PRumblePreference?
    private let cloudSync: CloudSaveSyncService?
    private let frontend = LibretroFrontend.shared

    // MARK: - Rumble
    private let rumbleOutput = RumbleOutput()
    /// Whether rumble is actually running for this session (switched on and a
    /// core that reports it). The in-game menu only offers the intensity when
    /// this is true, a slider that does nothing would be worse than none.
    private(set) var isRumbleActive = false

    var onMenuRequested: (() -> Void)?
    /// Reports whether the on-screen touch controls are currently hidden, so the
    /// SwiftUI layer can show a standalone menu button in their place.
    var onControlsHiddenChanged: ((Bool) -> Void)?

    let viewController: LibretroGameViewController

    /// Owned here so the display manager can hold it weakly: the target must not
    /// outlive the session it paints from.
    private var externalRenderTarget: LibretroExternalRenderTarget?

    // MARK: - Physical controller input bridge
    private let controllerInput: LibretroControllerInput
    /// The controller currently wired to the input bridge, if any.
    private var attachedController: GCController?

    init(
        gameURL: URL,
        core: LibretroCore,
        romId: Int,
        saveStates: PEmulatorSaveStatesUseCase,
        aspectRatioPreference: PLibretroAspectRatioPreference,
        screenPositionPreference: PEmulatorScreenPositionPreference,
        menuShortcutPreference: PEmulatorMenuShortcutPreference? = nil,
        faceButtonPreference: PGamepadFaceButtonPreference? = nil,
        rumblePreference: PRumblePreference? = nil,
        cloudSync: CloudSaveSyncService? = nil
    ) {
        self.gameURL = gameURL
        self.core = core
        self.romId = romId
        self.saveStates = saveStates
        self.aspectRatioPreference = aspectRatioPreference
        self.screenPositionPreference = screenPositionPreference
        self.rumblePreference = rumblePreference
        self.cloudSync = cloudSync
        self.externalRenderTarget = nil
        self.viewController = LibretroGameViewController(
            core: core,
            gameURL: gameURL,
            aspectRatioPreference: aspectRatioPreference,
            screenPositionPreference: screenPositionPreference
        )
        // controllerInput must be created before super.init() because stored
        // properties must be initialised before the instance escapes.
        // onMenuRequested is wired after super.init() once self is available.
        self.controllerInput = LibretroControllerInput(
            frontend: LibretroFrontend.shared,
            menuShortcutPreference: menuShortcutPreference,
            faceButtonPreference: faceButtonPreference
        )
        super.init()
        self.viewController.controllerView.onMenuTapped = { [weak self] in
            self?.onMenuRequested?()
        }
        self.viewController.onControlsHiddenChanged = { [weak self] hidden in
            self?.onControlsHiddenChanged?(hidden)
        }

        // Forward menu requests from the optional controller shortcut combo.
        controllerInput.onMenuRequested = { [weak self] in
            self?.onMenuRequested?()
        }

        // Wire connect/disconnect so the input bridge stays in sync.
        var names: [NSNotification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect]
        #if DEBUG
        names.append(.emulatorSimulatedControllerChanged)
        #endif
        for name in names {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleControllerConnectionChanged),
                name: name,
                object: nil
            )
        }

        // Attach to any controller that is already connected at launch.
        attachControllerIfPresent()
    }

    // MARK: - Lifecycle

    /// - Parameter resumeSlot: Save-state slot to auto-load once the core is
    ///   running, or `nil` to start fresh. The load is sequenced after the core
    ///   is loaded and performed while paused — the same safe path the in-game
    ///   menu uses. Loading into a running core makes pcsx_rearmed reject
    ///   `retro_unserialize`, so this must not race the boot.
    func start(resumeSlot: Int? = nil) {
        let videoView = viewController.videoView
        frontend.videoSink = videoView

        // Feed an external display the same frames. The manager decides when,
        // this only says how.
        let target = LibretroExternalRenderTarget(videoView: videoView)
        externalRenderTarget = target
        ExternalDisplayManager.shared.setRenderTarget(target)

        Task { [weak self] in
            guard let self else { return }
            await self.cloudSync?.pullBeforeLaunch()
            self.stageBatteryForCore()
            self.startCore()
            guard let slot = resumeSlot else { return }
            // Give the core a few frames so its serialize size is initialized,
            // then load while paused.
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.frontend.pause()
            do {
                try self.loadState(slot: slot)
            } catch {
                print("[Libretro] resume from slot \(slot) failed: \(error.localizedDescription)")
            }
            self.frontend.resume()
        }
    }

    /// Copies the canonical battery file out of `PSaveStore` into the libretro
    /// save directory so the core actually loads it on `retro_load_game`.
    /// Without this step, freshly pulled cloud saves are written to
    /// `Saves/<romId>/battery.sav` but the libretro core reads
    /// `LibretroSaves/<stem>.srm` — two different files, so the save never
    /// reaches the running game.
    private func stageBatteryForCore() {
        guard let data = try? saveStates.readBattery(romId: romId) else { return }
        let dir = libretroSaveDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stem = gameURL.deletingPathExtension().lastPathComponent
        let dst = dir.appendingPathComponent("\(stem).srm")
        do {
            try data.write(to: dst, options: .atomic)
            print("[Libretro] staged battery into saveDir (\(data.count) bytes)")
        } catch {
            print("[Libretro] failed to stage battery: \(error.localizedDescription)")
        }
    }

    // MARK: - HW-Render Meilenstein 1 (TEMPORAER)

    /// Schaltet den roten-Bildschirm-Test statt der echten Core-Startlogik ein.
    /// Beweist EAGL-Kontext + FBO + glReadPixels + Y-Flip + RGBA-CGImage-Mapping
    /// isoliert, ohne libretro-Core. Wird in Meilenstein 3 durch echte
    /// HW-Frames ersetzt. Zum Testen auf `true` setzen, danach wieder `false`.
    /// Bewusst hier isoliert, damit die bestehende Software-Pipeline unberuehrt
    /// bleibt.
    private static let hwRenderMilestone1Test = false

    /// Erzeugt einen roten FBO-Frame ueber den HW-Pfad und schickt ihn an den
    /// bestehenden Video-Sink (Software-Blit). Reines Debugging fuer M1.
    private func runHWRenderMilestone1Test() {
        let width = 640
        let height = 480

        guard hwRenderMakeContext() else {
            print("[HWRender] M1: Kontext-Erzeugung fehlgeschlagen")
            viewController.showError("HW-Render M1: GL-Kontext fehlgeschlagen")
            return
        }
        hwRenderSetupFramebuffer(Int32(width), Int32(height))

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ok = buffer.withUnsafeMutableBufferPointer { ptr -> Bool in
            hwRenderClearAndReadback(ptr.baseAddress, Int32(width), Int32(height))
        }
        guard ok else {
            print("[HWRender] M1: Readback fehlgeschlagen")
            viewController.showError("HW-Render M1: Readback fehlgeschlagen")
            return
        }

        print("[HWRender] M1: Testmuster-Frame an Video-Sink (\(width)x\(height))")
        buffer.withUnsafeBufferPointer { ptr in
            frontend.videoSink?.libretroDidProduceFrame(
                data: ptr.baseAddress,
                width: UInt32(width),
                height: UInt32(height),
                pitch: width * 4,
                pixelFormat: .rgba8888
            )
        }
    }

    private func startCore() {
        // TEMPORAER (Meilenstein 1): den roten-Bildschirm-Test statt des echten
        // Cores fahren. Laesst die Software-Core-Pipeline unangetastet.
        if Self.hwRenderMilestone1Test {
            runHWRenderMilestone1Test()
            return
        }

        do {
            let corePath = try locateCoreDylib()
            let systemDir = libretroSystemDirectory().path
            let saveDir = libretroSaveDirectory().path
            print("[Libretro] core=\(corePath)")
            print("[Libretro] system=\(systemDir) save=\(saveDir)")

            // pcsx_rearmed only reports rumble on a DualShock port, and that port
            // also changes what the core expects from us. With rumble switched
            // off we stay on the plain pad, which is exactly the old behaviour.
            // The preference is read once here, never per frame.
            let preference = rumblePreference
            let rumbleActive = (preference?.isEnabled ?? false) && core == .pcsxRearmed
            let portDevice = rumbleActive
                ? LibretroABI.DEVICE_PSE_DUALSHOCK
                : LibretroABI.DEVICE_JOYPAD

            try frontend.load(
                corePath: corePath,
                gamePath: gameURL.path,
                systemDir: systemDir,
                saveDir: saveDir,
                portDevice: portDevice
            )

            // Only after the core is up, so a failed load leaves no haptics
            // engine running and no hook dangling on the shared frontend. The
            // hook just has to be in place before the first frame runs.
            if rumbleActive, let preference {
                isRumbleActive = true
                rumbleOutput.scale = preference.intensity.scale
                rumbleOutput.start()
                rumbleOutput.attach(controller: attachedController)
                frontend.onRumbleChanged = { [weak self] strong, weak in
                    self?.rumbleOutput.setMotors(strong: strong, weak: weak)
                }
                print("[Libretro] rumble enabled (\(preference.intensity.rawValue))")
            }

            frontend.startRunLoop()
        } catch let error as LibretroFrontend.FrontendError {
            print("[Libretro] start failed: \(error.diagnosticDescription)")
            viewController.showError(error.localizedDescription)
        } catch {
            print("[Libretro] start failed: \(error.localizedDescription)")
            viewController.showError(error.localizedDescription)
        }
    }

    func pause() { frontend.pause() }
    func resume() { frontend.resume() }

    // MARK: - Physical controller input

    @objc private func handleControllerConnectionChanged() {
        // Release every button that might be latched on the outgoing controller
        // before re-evaluating; prevents permanently-stuck inputs across
        // connect/disconnect events.
        controllerInput.detach(from: attachedController)
        attachedController = nil
        // Back to the device haptics until a controller shows up again.
        rumbleOutput.attach(controller: nil)
        attachControllerIfPresent()
    }

    private func attachControllerIfPresent() {
        guard let controller = GCController.controllers().first else { return }
        attachedController = controller
        controllerInput.attach(to: controller)
        rumbleOutput.attach(controller: controller)
        print("[Libretro] physical controller attached: \(controller.vendorName ?? "unknown")")
    }

    func reloadAspectRatio() {
        viewController.applyAspectConstraints()
    }

    /// Picks up the face-button swap and the menu shortcut changed in the
    /// in-game menu, live. Both only affect how the input bridge reads the pad,
    /// so nothing about the running core has to be touched.
    func reloadControllerPreferences() {
        controllerInput.reloadPreferences(for: attachedController)
    }

    /// Picks up an intensity changed from the in-game menu, live. Only the
    /// scale is re-read: the on/off switch decides the controller port at load
    /// time and cannot be flipped while the core is running.
    func reloadRumbleIntensity() {
        guard isRumbleActive, let preference = rumblePreference else { return }
        rumbleOutput.scale = preference.intensity.scale
    }


    func stop() {
        // Detach the physical controller before tearing down the frontend so
        // clearAllButtons() runs while the frontend is still live.
        controllerInput.detach(from: attachedController)
        attachedController = nil
        // Unwire both sinks BEFORE tearing down the core: pcsx_rearmed can emit a
        // final video frame during retro_unload_game / retro_deinit, and after
        // dlclose() any CGImage backed by core memory would crash on render.
        ExternalDisplayManager.shared.setRenderTarget(nil)
        externalRenderTarget = nil
        frontend.videoSink = nil
        frontend.stop()
        rumbleOutput.stop()
        isRumbleActive = false
        flushBatteryFromSaveDir()
    }

    /// Libretro cores persist their battery saves (.srm) into `saveDir` during
    /// runtime — we read the file once the core has stopped and push it.
    private func flushBatteryFromSaveDir() {
        let stem = gameURL.deletingPathExtension().lastPathComponent
        let candidate = libretroSaveDirectory().appendingPathComponent("\(stem).srm")
        guard let data = try? Data(contentsOf: candidate) else { return }
        try? saveStates.writeBattery(romId: romId, data: data)
        cloudSync?.pushBattery(data: data)
    }

    // MARK: - Save state API (mirrors DeltaCoreSession)

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

    func saveState(slot: Int) throws {
        guard let data = frontend.saveStateData() else {
            throw LibretroFrontend.FrontendError.symbolMissing("retro_serialize")
        }
        try saveStates.backupSlotForUndoSave(romId: romId, slot: slot)
        try saveStates.writeState(romId: romId, slot: slot, data: data)
        let thumb = viewController.videoView.snapshot()?.pngData()
        if let thumb {
            try saveStates.writeThumbnail(romId: romId, slot: slot, data: thumb)
        }
        cloudSync?.pushState(slot: slot, data: data, thumbnail: thumb)
    }

    func loadState(slot: Int) throws {
        guard let data = try saveStates.readState(romId: romId, slot: slot) else { return }
        if let snapshot = frontend.saveStateData() {
            let thumb = viewController.videoView.snapshot()?.pngData()
            try saveStates.writeUndoLoadSnapshot(romId: romId, stateData: snapshot, thumbnailData: thumb)
        }
        guard frontend.loadStateData(data) else {
            throw LibretroFrontend.FrontendError.symbolMissing("retro_unserialize")
        }
        // Discard audio queued before the jump so sound doesn't trail the picture.
        frontend.flushAudio()
    }

    func undoSave(slot: Int) throws {
        _ = try saveStates.restoreSlotFromUndoSave(romId: romId, slot: slot)
    }

    func undoLoad() throws {
        guard let data = try saveStates.readUndoLoadState(romId: romId) else { return }
        guard frontend.loadStateData(data) else {
            throw LibretroFrontend.FrontendError.symbolMissing("retro_unserialize")
        }
        try saveStates.clearUndoLoad(romId: romId)
    }

    // MARK: - Paths

    /// Dylib-Lookup. Konvention:
    ///   1. App-Bundle: `Frameworks/<dylibName>.framework/<dylibName>`
    ///   2. App-Bundle: `Frameworks/<dylibName>.dylib`
    ///   3. Documents/LibretroCores/<dylibName>.dylib  (manueller Sideload via Files-App)
    private func locateCoreDylib() throws -> String {
        let name = core.dylibName

        if let url = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("\(name).framework", isDirectory: true)
            .appendingPathComponent(name),
           FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        if let url = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("\(name).dylib"),
           FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }

        let docCandidate = documentsDirectory()
            .appendingPathComponent("LibretroCores", isDirectory: true)
            .appendingPathComponent("\(name).dylib")
        if FileManager.default.fileExists(atPath: docCandidate.path) {
            return docCandidate.path
        }
        throw LibretroFrontend.FrontendError.dylibNotFound(name)
    }

    private func libretroSystemDirectory() -> URL {
        documentsDirectory().appendingPathComponent("LibretroSystem", isDirectory: true)
    }

    private func libretroSaveDirectory() -> URL {
        documentsDirectory().appendingPathComponent("LibretroSaves", isDirectory: true)
    }

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

final class LibretroGameViewController: UIViewController {
    private let core: LibretroCore
    private let gameURL: URL
    private let aspectRatioPreference: PLibretroAspectRatioPreference
    private let screenPositionPreference: PEmulatorScreenPositionPreference
    let videoView = LibretroVideoView()
    let controllerView: LibretroTouchControllerView
    var onControlsHiddenChanged: ((Bool) -> Void)?
    private var controlsHidden = false
    private let errorLabel = UILabel()
    private var aspectConstraint: NSLayoutConstraint?
    /// Top-anchor constraint used to slide the video within the safe area when
    /// custom placement is active. Its constant is recomputed each layout pass.
    private var verticalConstraint: NSLayoutConstraint?

    /// `verticalOffset` captured at the start of a drag, so the whole gesture is
    /// applied relative to it.
    private var basePanOffset: Double?

    /// Lets the user drag the game vertically. Only enabled while the touch
    /// controls are hidden (a physical controller is connected).
    private lazy var screenPanRecognizer: UIPanGestureRecognizer = {
        let r = UIPanGestureRecognizer(target: self, action: #selector(handleScreenPan(_:)))
        r.isEnabled = false
        return r
    }()

    init(
        core: LibretroCore,
        gameURL: URL,
        aspectRatioPreference: PLibretroAspectRatioPreference,
        screenPositionPreference: PEmulatorScreenPositionPreference
    ) {
        self.core = core
        self.gameURL = gameURL
        self.aspectRatioPreference = aspectRatioPreference
        self.screenPositionPreference = screenPositionPreference
        let controllerLayout: LibretroTouchControllerView.Layout
        switch core {
        case .beetlePCEFast: controllerLayout = .pcEngine
        case .genesisPlusGX: controllerLayout = .genesis
        default: controllerLayout = .standard
        }
        self.controllerView = LibretroTouchControllerView(layout: controllerLayout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Re-apply placement + control visibility when a physical controller
        // connects/disconnects, live during a session.
        var connectionNames: [NSNotification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect]
        #if DEBUG
        connectionNames.append(.emulatorSimulatedControllerChanged)
        #endif
        for name in connectionNames {
            NotificationCenter.default.addObserver(
                self, selector: #selector(controllerConnectionChanged), name: name, object: nil
            )
        }

        videoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoView)
        applyAspectConstraints()
        view.addGestureRecognizer(screenPanRecognizer)

        controllerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controllerView)
        NSLayoutConstraint.activate([
            controllerView.topAnchor.constraint(equalTo: view.topAnchor),
            controllerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controllerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controllerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        updateControlsVisibility()

        errorLabel.numberOfLines = 0
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.font = .systemFont(ofSize: 14, weight: .medium)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true
        view.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
    }

    func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.controllerView.setNeedsLayout()
            self?.controllerView.layoutIfNeeded()
            // Portrait/landscape flips whether custom placement applies.
            self?.applyAspectConstraints()
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Pick up changes made from settings while paused in the menu overlay.
        applyAspectConstraints()
        updateControlsVisibility()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateVerticalOffsetConstant()
    }

    @objc private func controllerConnectionChanged() {
        applyAspectConstraints()
        updateControlsVisibility()
    }

    /// Hide the touch overlay when a physical controller is connected; a
    /// standalone menu button (SwiftUI) then provides access to the in-game
    /// menu, and the game becomes draggable.
    private func updateControlsVisibility() {
        let hide = EmulatorControllerState.isConnected
        controllerView.isHidden = hide
        screenPanRecognizer.isEnabled = hide
        if hide != controlsHidden {
            controlsHidden = hide
            onControlsHiddenChanged?(hide)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Re-installs the aspect constraint for `videoView` based on the user's
    /// preference. Only PSX (libretro) games go through this controller, so we
    /// just read the PSX preference directly.
    func applyAspectConstraints() {
        aspectConstraint?.isActive = false
        aspectConstraint = nil
        verticalConstraint = nil

        // Common constraints — center + don't exceed view bounds, prefer to fill.
        // We rebuild from scratch to keep this idempotent across pref changes.
        view.constraints
            .filter { ($0.firstItem as? UIView) === videoView || ($0.secondItem as? UIView) === videoView }
            .forEach { view.removeConstraint($0) }

        let widthLimit = videoView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor)
        let widthFill = videoView.widthAnchor.constraint(equalTo: view.widthAnchor)
        widthFill.priority = .defaultHigh

        // Controller Mode: when active (see `isCustomPlacementActive`) the video
        // is limited to a user-chosen fraction of the safe-area height and slid
        // vertically via a top-anchor constant (recomputed in layout, because
        // the actual height depends on the aspect ratio). Otherwise it fills the
        // whole view and centers, as before.
        let vertical: NSLayoutConstraint
        let heightLimit: NSLayoutConstraint
        let heightFill: NSLayoutConstraint
        if isCustomPlacementActive {
            let fraction = CGFloat(min(1.0, max(0.3, screenPositionPreference.heightFraction)))
            let guide = view.safeAreaLayoutGuide
            let top = videoView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 0)
            verticalConstraint = top
            vertical = top
            heightLimit = videoView.heightAnchor.constraint(lessThanOrEqualTo: guide.heightAnchor, multiplier: fraction)
            heightFill = videoView.heightAnchor.constraint(equalTo: guide.heightAnchor, multiplier: fraction)
            heightFill.priority = .defaultHigh
        } else {
            vertical = videoView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            heightLimit = videoView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor)
            heightFill = videoView.heightAnchor.constraint(equalTo: view.heightAnchor)
            heightFill.priority = .defaultHigh
        }

        NSLayoutConstraint.activate([
            videoView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            vertical,
            widthLimit, heightLimit, widthFill, heightFill
        ])

        if let ratio = aspectRatioPreference.psx.ratio {
            let c = videoView.widthAnchor.constraint(equalTo: videoView.heightAnchor, multiplier: ratio)
            c.isActive = true
            aspectConstraint = c
        }

        view.layoutIfNeeded()
        updateVerticalOffsetConstant()
    }

    /// Whether the user's custom vertical placement should apply right now: only
    /// while a physical controller is connected, portrait only (in landscape the
    /// game already fills the height).
    private var isCustomPlacementActive: Bool {
        guard view.bounds.height >= view.bounds.width else { return false }
        return EmulatorControllerState.isConnected
    }

    /// Drag-to-move handler: converts the vertical pan into a `verticalOffset`
    /// (0…1) relative to where the drag started, then slides the video live.
    @objc private func handleScreenPan(_ gesture: UIPanGestureRecognizer) {
        guard isCustomPlacementActive else { return }
        switch gesture.state {
        case .began:
            basePanOffset = screenPositionPreference.verticalOffset
        case .changed:
            let free = max(1, view.safeAreaLayoutGuide.layoutFrame.height - videoView.frame.height)
            let base = basePanOffset ?? screenPositionPreference.verticalOffset
            let delta = Double(gesture.translation(in: view).y / free)
            screenPositionPreference.verticalOffset = min(1.0, max(0.0, base + delta))
            updateVerticalOffsetConstant()
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            basePanOffset = nil
        default:
            break
        }
    }

    /// Slides the video within the safe area to the user's vertical offset.
    /// `0` = flush top, `0.5` = centered, `1` = flush bottom. Runs from
    /// `viewDidLayoutSubviews` because it needs the resolved video height.
    private func updateVerticalOffsetConstant() {
        guard let top = verticalConstraint else { return }
        let guideHeight = view.safeAreaLayoutGuide.layoutFrame.height
        let videoHeight = videoView.frame.height
        let free = max(0, guideHeight - videoHeight)
        let offset = CGFloat(min(1.0, max(0.0, screenPositionPreference.verticalOffset)))
        let target = (offset * free).rounded()
        if abs(target - top.constant) > 0.5 {
            top.constant = target
        }
    }
}
