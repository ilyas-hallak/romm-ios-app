import UIKit
import Combine

/// Owns the window we put on an external display (AirPlay or a USB-C/HDMI
/// adapter) so a running game can be shown there directly instead of letting the
/// system mirror the whole phone UI.
///
/// How the system side works: while AirPlaying or wired up, iOS offers the app a
/// scene with the `windowExternalDisplayNonInteractive` role. As long as we
/// render nothing into that scene, the system falls back to plain mirroring.
/// Attaching a `UIWindow` to it takes over the display; setting the window's
/// `windowScene` back to nil hands it back to mirroring. That is exactly the
/// switch `isActive` drives, which also makes an A/B comparison possible from
/// the in-game menu.
///
/// Why this beats mirroring even though it cannot beat the AirPlay latency: the
/// game is rendered at the TV's own resolution and aspect, so no portrait phone
/// screen with black bars, and only the game picture has to be encoded instead
/// of the entire animated UI.
///
/// Scope of this class: scene and window plumbing, plus the observable state the
/// UI binds to. The *decision* lives in `ExternalDisplayPolicy` and the painting
/// in a `PExternalRenderTarget`, so neither is entangled with UIKit lifecycle.
///
/// A singleton because UIKit instantiates `ExternalDisplaySceneDelegate` itself
/// and hands it a scene, so there is no call site to inject into. The same reason
/// `LibretroFrontend` is one. Its collaborators come through the initialiser, but
/// the window path still needs a live `UIWindowScene`, which cannot be built in a
/// test, so nothing here is driven by one yet.
@MainActor
final class ExternalDisplayManager: ObservableObject {

    static let shared = ExternalDisplayManager(
        preference: DefaultDependencyFactory.shared.externalDisplayPreference,
        diagnostics: DefaultDependencyFactory.shared.externalDisplayDiagnostics
    )

    /// True while iOS has handed us an external display scene.
    @Published private(set) var isConnected = false

    /// True while we are painting the display ourselves. False means the system
    /// mirrors the phone as usual.
    @Published private(set) var isActive = false

    /// Pixel size of the attached display, for the status line in the in-game
    /// menu. iOS exposes no name for an external screen, so the resolution is
    /// the only concrete thing we can show.
    @Published private(set) var displayResolution: String?

    /// Mirrors the preference, unlike the plain forwarders below: the running
    /// emulator view observes this directly, so flipping it from the in-game
    /// menu has to take effect without a relaunch.
    @Published private(set) var isPhoneControllerOnlyEnabled: Bool

    private let preference: PExternalDisplayPreference

    /// Every state change here is also a measurement point for the AirPlay
    /// latency question, see `ExternalDisplayDiagnostics`.
    private let diagnostics: PExternalDisplayDiagnostics

    /// Fills the display whenever we own it. Exists independently of whether one
    /// is attached, so a render target can be handed it and forget about
    /// connection state.
    private let contentView = ExternalDisplayContentView()

    /// Set while an emulator session is on screen. Outside a session we leave
    /// the display alone, mirroring the library UI is the sensible default there.
    private var isSessionRunning = false

    private weak var scene: UIWindowScene?
    private var window: UIWindow?

    /// Weak: the running session owns its render target and outlives no session.
    private weak var renderTarget: PExternalRenderTarget?

    init(
        preference: PExternalDisplayPreference,
        diagnostics: PExternalDisplayDiagnostics
    ) {
        self.preference = preference
        self.diagnostics = diagnostics
        self.isPhoneControllerOnlyEnabled = preference.isPhoneControllerOnlyEnabled
    }

    // MARK: - Scene lifecycle (called from ExternalDisplaySceneDelegate)

    func sceneDidConnect(_ scene: UIWindowScene) {
        diagnostics.displayDidConnect(ExternalDisplayMetrics(screen: scene.screen))
        self.scene = scene
        isConnected = true
        let px = scene.screen.nativeBounds.size
        displayResolution = "\(Int(px.width)) × \(Int(px.height))"
        sync()
    }

    func sceneDidDisconnect(_ scene: UIWindowScene) {
        guard self.scene === scene else { return }
        diagnostics.displayDidDisconnect()
        self.scene = nil
        isConnected = false
        displayResolution = nil
        sync()
    }

    // MARK: - Session lifecycle (called from the emulator views)

    func beginSession() {
        isSessionRunning = true
        diagnostics.sessionDidBegin()
        sync()
    }

    func endSession() {
        isSessionRunning = false
        sync()
        // After `sync()`: tearing the window down logs one last time, and the
        // route reading belongs to the session that is ending.
        diagnostics.sessionDidEnd()
    }

    /// Registered by the running emulator session. Setting it while we already
    /// own the display starts it right away, which is the case when a game is
    /// launched with a TV already attached.
    func setRenderTarget(_ target: PExternalRenderTarget?) {
        if let previous = renderTarget, previous !== target {
            previous.stopRendering()
        }
        renderTarget = target
        syncRendering()
    }

    // MARK: - User control

    var isPlayOnTVEnabled: Bool { preference.isPlayOnTVEnabled }

    /// Lets the player hand the display back to plain mirroring and take it over
    /// again, from the in-game menu or from Settings.
    func setPlayOnTVEnabled(_ enabled: Bool) {
        preference.isPlayOnTVEnabled = enabled
        sync()
    }

    var isAutoDimPhoneEnabled: Bool { preference.isAutoDimPhoneEnabled }

    func setAutoDimPhoneEnabled(_ enabled: Bool) {
        preference.isAutoDimPhoneEnabled = enabled
    }

    /// Lets the player turn the phone into a pure controller while the game
    /// plays on the TV. The engine views watch `isPhoneControllerOnlyEnabled`
    /// themselves to decide what that means for their own video layer.
    func setPhoneControllerOnlyEnabled(_ enabled: Bool) {
        preference.isPhoneControllerOnlyEnabled = enabled
        isPhoneControllerOnlyEnabled = enabled
    }

    /// The policy's verdict for this display, so the call sites do not each have
    /// to know which of its fields feed the decision.
    func isPhoneVideoHidden(areTouchControlsHidden: Bool) -> Bool {
        ExternalDisplayPolicy.shouldHidePhoneVideo(
            isRenderingExternally: isActive,
            isPhoneControllerOnlyEnabled: isPhoneControllerOnlyEnabled,
            areTouchControlsHidden: areTouchControlsHidden
        )
    }

    // MARK: - Window plumbing

    /// Single place that acts on the policy's verdict, so every entry point above
    /// just changes state and calls this.
    private func sync() {
        let shouldRender = ExternalDisplayPolicy.shouldRenderExternally(
            isDisplayConnected: isConnected,
            isSessionRunning: isSessionRunning,
            isPlayOnTVEnabled: preference.isPlayOnTVEnabled
        )
        if shouldRender {
            setupWindow()
        } else {
            teardownWindow()
        }
        isActive = window != nil
        syncRendering()
    }

    private func syncRendering() {
        guard let renderTarget else { return }
        if isActive {
            renderTarget.startRendering(into: contentView)
            // Reported from here rather than from `setupWindow()`: a game
            // launched with a display already attached registers its target
            // afterwards, and only the target knows whether frames are counted.
            if let scene {
                diagnostics.renderingDidStart(
                    on: ExternalDisplayMetrics(screen: scene.screen),
                    countingFrames: renderTarget.reportsFrameRate
                )
            }
        } else {
            renderTarget.stopRendering()
        }
    }

    private func setupWindow() {
        guard window == nil, let scene else { return }
        let controller = ExternalDisplayViewController(contentView: contentView)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
    }

    private func teardownWindow() {
        guard let window else { return }
        // Detaching from the scene is what makes iOS resume mirroring.
        window.isHidden = true
        window.windowScene = nil
        self.window = nil
        diagnostics.renderingDidStop()
    }
}

/// The picture surface itself, kept apart from the window so it survives the
/// display being handed back and forth between us and plain mirroring.
final class ExternalDisplayContentView: UIView, PExternalDisplaySurface {

    /// Keys whose implicit animation would be visible on a live picture. A
    /// layer that backs a `UIView` gets these suppressed by the view acting as
    /// its delegate. This one stands on its own, so it has to say so itself.
    static let unanimatedKeys = ["contents", "contentsRect", "contentsScale", "bounds", "position"]

    let videoLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor.black.cgColor
        // Nearest keeps the pixel art crisp when blown up to a TV, resizeAspect
        // does the letterboxing for us whatever the panel's ratio is.
        layer.magnificationFilter = .nearest
        layer.contentsGravity = .resizeAspect
        // Without this every assigned frame is cross faded into the previous one
        // over a quarter of a second, Core Animation's default action for a
        // layer nobody vouches for. At 60 assignments a second that leaves a
        // permanently dissolving, trailing picture on the TV while the phone,
        // whose layer belongs to a view, looks perfectly sharp.
        layer.actions = Dictionary(uniqueKeysWithValues: ExternalDisplayContentView.unanimatedKeys.map { ($0, NSNull()) })
        return layer
    }()

    private weak var installedContent: UIView?

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(videoLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func setContent(_ view: UIView?) {
        installedContent?.removeFromSuperview()
        installedContent = view
        guard let view else { return }
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }

    /// A standalone layer starts at scale 1 and never inherits one, so it is
    /// given the external screen's own. `resizeAspect` fits the picture to the
    /// bounds either way, this is about the layer being described in the terms
    /// of the display it is on rather than about any single frame.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let screen = window?.screen else { return }
        videoLayer.contentsScale = screen.scale
        videoLayer.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // No animation: this is re-framed on resize and an implicit fade would
        // smear a live game picture.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}

/// Black full-bleed host for the content view. Non-interactive by definition of
/// the scene role, so there is nothing to wire up beyond the layout.
private final class ExternalDisplayViewController: UIViewController {

    private let contentView: ExternalDisplayContentView

    init(contentView: ExternalDisplayContentView) {
        self.contentView = contentView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        contentView.frame = view.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentView)
    }
}
