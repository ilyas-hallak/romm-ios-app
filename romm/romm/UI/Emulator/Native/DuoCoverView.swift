#if !APP_STORE
import UIKit
import DeltaCore

/// An accessible dismissal surface for a skin's cover artwork.
@available(iOS 27.1, *)
final class DuoCoverView: UIView {
    let controllerSkin: any ControllerSkinProtocol
    var onDismiss: (() -> Void)?
    private(set) var isCoverHidden = true

    private let contentView = UIView()
    private let artwork = UIImageView()
    private let dismissButton = UIButton(type: .system)
    private var visibilityRevision = 0
    private var previousBatteryMonitoring: Bool?

    init(controllerSkin: any ControllerSkinProtocol) {
        self.controllerSkin = controllerSkin
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true
        accessibilityViewIsModal = true
        isHidden = true
        contentView.backgroundColor = .black
        contentView.alpha = 0
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        artwork.contentMode = .scaleAspectFit
        artwork.isAccessibilityElement = false
        artwork.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(artwork)

        var style = UIButton.Configuration.filled()
        style.title = String(localized: "Open console")
        style.image = UIImage(systemName: "chevron.up")
        style.imagePlacement = .top
        style.imagePadding = 6
        style.cornerStyle = .capsule
        style.baseForegroundColor = .white
        style.baseBackgroundColor = .black.withAlphaComponent(0.65)
        style.contentInsets = .init(top: 10, leading: 20, bottom: 10, trailing: 20)
        dismissButton.configuration = style
        dismissButton.accessibilityHint = String(localized: "Dismisses the closed-console cover.")
        dismissButton.addTarget(self, action: #selector(dismissCover), for: .touchUpInside)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dismissButton)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: trailingAnchor),
            artwork.topAnchor.constraint(equalTo: topAnchor),
            artwork.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissButton.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            dismissButton.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            dismissButton.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            dismissButton.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor),
            dismissButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissCover))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissCover))
        swipe.direction = .up
        addGestureRecognizer(swipe)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshArtwork),
            name: UIDevice.batteryStateDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(controllerSkin:)") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            if let previousBatteryMonitoring {
                UIDevice.current.isBatteryMonitoringEnabled = previousBatteryMonitoring
                self.previousBatteryMonitoring = nil
            }
        } else {
            if previousBatteryMonitoring == nil {
                previousBatteryMonitoring = UIDevice.current.isBatteryMonitoringEnabled
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            refreshArtwork()
        }
    }

    func showCover(animated: Bool = true) {
        guard isCoverHidden else { return }
        visibilityRevision += 1
        let revision = visibilityRevision
        isCoverHidden = false
        isHidden = false
        refreshArtwork()
        setVisibility(alpha: 1, animated: animated) { [weak self] in
            guard let self, self.visibilityRevision == revision, !self.isCoverHidden else { return }
            UIAccessibility.post(notification: .screenChanged, argument: self.dismissButton)
        }
    }

    @objc private func dismissCover() {
        guard !isCoverHidden else { return }
        visibilityRevision += 1
        let revision = visibilityRevision
        isCoverHidden = true
        setVisibility(alpha: 0, animated: true) { [weak self] in
            guard let self, self.visibilityRevision == revision, self.isCoverHidden else { return }
            self.isHidden = true
            self.onDismiss?()
        }
    }

    private func setVisibility(alpha: CGFloat, animated: Bool, completion: @escaping () -> Void) {
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            contentView.alpha = alpha
            completion()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.contentView.alpha = alpha
        } completion: { _ in completion() }
    }

    @objc private func refreshArtwork() {
        guard let window else { return }
        var traits = ControllerSkin.Traits.defaults(for: window)
        traits.displayType = .cover
        traits.orientation = .landscape
        let charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        let normal = controllerSkin.image(for: traits, preferredSize: .large)
        artwork.image = charging
            ? controllerSkin.pressedImage(for: traits, preferredSize: .large) ?? normal
            : normal
    }
}
#endif
