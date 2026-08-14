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
    private let cloudSync: CloudSaveSyncService?
    private let frontend = LibretroFrontend.shared

    var onMenuRequested: (() -> Void)?
    /// Reports whether the on-screen touch controls are currently hidden, so the
    /// SwiftUI layer can show a standalone menu button in their place.
    var onControlsHiddenChanged: ((Bool) -> Void)?

    let viewController: LibretroGameViewController

    init(
        gameURL: URL,
        core: LibretroCore,
        romId: Int,
        saveStates: PEmulatorSaveStatesUseCase,
        aspectRatioPreference: PLibretroAspectRatioPreference,
        screenPositionPreference: PEmulatorScreenPositionPreference,
        cloudSync: CloudSaveSyncService? = nil
    ) {
        self.gameURL = gameURL
        self.core = core
        self.romId = romId
        self.saveStates = saveStates
        self.aspectRatioPreference = aspectRatioPreference
        self.screenPositionPreference = screenPositionPreference
        self.cloudSync = cloudSync
        self.viewController = LibretroGameViewController(
            core: core,
            gameURL: gameURL,
            aspectRatioPreference: aspectRatioPreference,
            screenPositionPreference: screenPositionPreference
        )
        super.init()
        self.viewController.controllerView.onMenuTapped = { [weak self] in
            self?.onMenuRequested?()
        }
        self.viewController.onControlsHiddenChanged = { [weak self] hidden in
            self?.onControlsHiddenChanged?(hidden)
        }
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

    private func startCore() {
        do {
            let corePath = try locateCoreDylib()
            let systemDir = libretroSystemDirectory().path
            let saveDir = libretroSaveDirectory().path
            print("[Libretro] core=\(corePath)")
            print("[Libretro] system=\(systemDir) save=\(saveDir)")
            try frontend.load(
                corePath: corePath,
                gamePath: gameURL.path,
                systemDir: systemDir,
                saveDir: saveDir
            )
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

    func reloadAspectRatio() {
        viewController.applyAspectConstraints()
    }

    func stop() {
        // Unwire the sink BEFORE tearing down the core: pcsx_rearmed can emit a
        // final video frame during retro_unload_game / retro_deinit, and after
        // dlclose() any CGImage backed by core memory would crash on render.
        frontend.videoSink = nil
        frontend.stop()
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
