#if !APP_STORE
// Adapted from Delta's CoverView.swift, created by Riley Testut on 10/10/26.
// Copyright © 2026 Riley Testut. All rights reserved.
// RomM integration keeps emulation and pause ownership in NativeEmulatorSession.

import UIKit
import DeltaCore

/// Presents the controller skin's closed-console artwork without forwarding
/// touches to the game. The session removes this view after `onDismiss` fires.
@available(iOS 27.1, *)
final class DuoCoverView: UIView {
    let controllerSkin: any ControllerSkinProtocol
    var onDismiss: (() -> Void)?

    private(set) var isCoverHidden = true

    private let coverContentView = UIView()
    private let imageView = UIImageView()
    private let openButton = UIButton(type: .system)
    private var animator: UIViewPropertyAnimator?
    private var previousBatteryMonitoringState: Bool?

    init(controllerSkin: any ControllerSkinProtocol) {
        self.controllerSkin = controllerSkin
        super.init(frame: .zero)

        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        accessibilityViewIsModal = true

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        coverContentView.addSubview(imageView)
        addSubview(coverContentView)

        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "Open console")
        configuration.image = UIImage(systemName: "chevron.up")
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.65)
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
        openButton.configuration = configuration
        openButton.accessibilityHint = String(localized: "Dismisses the closed-console cover.")
        openButton.addTarget(self, action: #selector(openCover), for: .touchUpInside)
        coverContentView.addSubview(openButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(openCover))
        // Keep the explicit button's highlight and accessibility behavior.
        tap.cancelsTouchesInView = false
        coverContentView.addGestureRecognizer(tap)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(openCover))
        swipe.direction = .up
        coverContentView.addGestureRecognizer(swipe)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange(_:)),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        coverContentView.frame = bounds.offsetBy(dx: 0, dy: isCoverHidden ? -bounds.height : 0)
        imageView.frame = coverContentView.bounds

        let availableWidth = max(0, bounds.width - safeAreaInsets.left - safeAreaInsets.right - 32)
        let size = openButton.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
        let buttonWidth = min(availableWidth, size.width)
        let buttonHeight = max(44, size.height)
        openButton.frame = CGRect(
            x: safeAreaInsets.left + (availableWidth + 32 - buttonWidth) / 2,
            y: max(safeAreaInsets.top, bounds.height - safeAreaInsets.bottom - buttonHeight - 16),
            width: buttonWidth,
            height: buttonHeight
        )
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil {
            if previousBatteryMonitoringState == nil {
                previousBatteryMonitoringState = UIDevice.current.isBatteryMonitoringEnabled
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            updateImage()
        } else if let previousBatteryMonitoringState {
            UIDevice.current.isBatteryMonitoringEnabled = previousBatteryMonitoringState
            self.previousBatteryMonitoringState = nil
        }
    }

    func showCover(animated: Bool = true) {
        guard isCoverHidden else { return }
        updateCover(isHidden: false, animated: animated)
    }

    private func hideCover(animated: Bool = true) {
        guard !isCoverHidden else { return }
        updateCover(isHidden: true, animated: animated)
    }

    private func updateCover(isHidden: Bool, animated: Bool) {
        animator?.stopAnimation(true)
        animator = nil
        layoutIfNeeded()
        isCoverHidden = isHidden
        setNeedsLayout()

        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            layoutIfNeeded()
            if isHidden { onDismiss?() }
            else { UIAccessibility.post(notification: .screenChanged, argument: openButton) }
            return
        }

        let animator = UIViewPropertyAnimator(duration: 0.35, dampingRatio: 0.9) { [weak self] in
            self?.layoutIfNeeded()
        }
        animator.addCompletion { [weak self] _ in
            guard let self else { return }
            self.animator = nil
            if isHidden, self.isCoverHidden {
                self.onDismiss?()
            } else if !self.isCoverHidden {
                UIAccessibility.post(notification: .screenChanged, argument: self.openButton)
            }
        }
        self.animator = animator
        animator.startAnimation()
    }

    private func updateImage() {
        guard let window else { return }

        // Delta's cover artwork is a landscape representation on both displays.
        var traits = ControllerSkin.Traits.defaults(for: window)
        traits.displayType = .cover
        traits.orientation = .landscape

        switch UIDevice.current.batteryState {
        case .charging, .full:
            imageView.image = controllerSkin.pressedImage(for: traits, preferredSize: .large)
                ?? controllerSkin.image(for: traits, preferredSize: .large)
        case .unknown, .unplugged:
            imageView.image = controllerSkin.image(for: traits, preferredSize: .large)
        @unknown default:
            imageView.image = controllerSkin.image(for: traits, preferredSize: .large)
        }
    }

    @objc private func openCover() {
        hideCover()
    }

    @objc private func batteryStateDidChange(_ notification: Notification) {
        updateImage()
    }
}
#endif
