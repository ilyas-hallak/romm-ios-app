import UIKit
import Combine

/// Owns the window we put on an external display (AirPlay or a USB-C/HDMI
/// adapter) so a running game can be shown there directly instead of letting
/// the system mirror the whole phone UI.
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
@MainActor
final class ExternalDisplayManager: ObservableObject {

    static let shared = ExternalDisplayManager()

    /// Layer the renderers push their frames into. It exists independently of
    /// whether a display is attached right now, so a renderer can wire it up
    /// once in `viewDidLoad` and never think about connection state again. While
    /// nothing is attached the layer is not in any hierarchy and assigning
    /// `contents` is close to free.
    let videoLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor.black.cgColor
        // Nearest keeps the pixel art crisp when blown up to a TV, resizeAspect
        // does the letterboxing for us whatever the panel's ratio is.
        layer.magnificationFilter = .nearest
        layer.contentsGravity = .resizeAspect
        return layer
    }()

    /// True while iOS has handed us an external display scene.
    @Published private(set) var isConnected = false

    /// True while we are painting the display ourselves. False means the system
    /// mirrors the phone as usual.
    @Published private(set) var isActive = false

    /// Pixel size of the attached display, for the status line in the in-game
    /// menu. iOS exposes no name for an external screen, so the resolution is
    /// the only concrete thing we can show.
    @Published private(set) var displayResolution: String?

    /// Set while an emulator session is on screen. Outside a session we leave
    /// the display alone, mirroring the library UI is the sensible default there.
    private var isSessionRunning = false

    private weak var scene: UIWindowScene?
    private var window: UIWindow?

    private init() {}

    // MARK: - Scene lifecycle (called from ExternalDisplaySceneDelegate)

    func sceneDidConnect(_ scene: UIWindowScene) {
        print("[ExternalDisplay] scene connected, \(Int(scene.screen.bounds.width))x\(Int(scene.screen.bounds.height))")
        self.scene = scene
        isConnected = true
        let px = scene.screen.nativeBounds.size
        displayResolution = "\(Int(px.width)) × \(Int(px.height))"
        syncWindow()
    }

    func sceneDidDisconnect(_ scene: UIWindowScene) {
        guard self.scene === scene else { return }
        print("[ExternalDisplay] scene disconnected")
        teardownWindow()
        self.scene = nil
        isConnected = false
        isActive = false
        displayResolution = nil
    }

    // MARK: - Session lifecycle (called from the emulator view controllers)

    func beginSession() {
        isSessionRunning = true
        syncWindow()
    }

    func endSession() {
        isSessionRunning = false
        syncWindow()
    }

    // MARK: - User control

    /// Lets the player hand the display back to plain mirroring and take it over
    /// again, from the in-game menu.
    func setEnabled(_ enabled: Bool) {
        ExternalDisplayPreferences.isEnabled = enabled
        syncWindow()
    }

    var isEnabled: Bool { ExternalDisplayPreferences.isEnabled }

    // MARK: - Window plumbing

    /// Single place that decides whether our window should be up, so every entry
    /// point above just changes state and calls this.
    private func syncWindow() {
        let shouldShow = isConnected && isSessionRunning && ExternalDisplayPreferences.isEnabled
        if shouldShow {
            setupWindow()
        } else {
            teardownWindow()
        }
        isActive = window != nil
    }

    private func setupWindow() {
        guard window == nil, let scene else { return }
        let controller = ExternalDisplayViewController(videoLayer: videoLayer)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        print("[ExternalDisplay] took over the display")
    }

    private func teardownWindow() {
        guard let window else { return }
        // Detaching from the scene is what makes iOS resume mirroring.
        window.isHidden = true
        window.windowScene = nil
        self.window = nil
        print("[ExternalDisplay] released the display back to mirroring")
    }
}

/// Black full-bleed host for `videoLayer`. Non-interactive by definition of the
/// scene role, so there is nothing to wire up beyond the layer's frame.
private final class ExternalDisplayViewController: UIViewController {

    private let videoLayer: CALayer

    init(videoLayer: CALayer) {
        self.videoLayer = videoLayer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(videoLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // No animation: the layer is re-framed on rotation/resize and an implicit
        // fade would smear a live game picture.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = view.bounds
        CATransaction.commit()
    }
}

/// Persisted opt-out, kept next to the other lightweight emulator toggles
/// (see `HapticsPreferences`) rather than going through the DI container, since
/// only the manager reads it. Defaults to on: once a TV is attached, a portrait
/// phone screen with black bars is never what the player wanted.
enum ExternalDisplayPreferences {
    private static let enabledKey = "externalDisplay.enabled"
    private static let autoDimKey = "externalDisplay.autoDimPhone"

    static var isEnabled: Bool {
        get { boolOrTrue(enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Dim the handset on its own once the game is on the TV and a controller is
    /// in use. On by default: in that situation nobody is looking at the phone,
    /// and having to reach for a menu button to darken it defeats the point.
    static var autoDimPhone: Bool {
        get { boolOrTrue(autoDimKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoDimKey) }
    }

    /// `UserDefaults.bool` returns false for a missing key, which would make
    /// both of these default to off.
    private static func boolOrTrue(_ key: String) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }
}
