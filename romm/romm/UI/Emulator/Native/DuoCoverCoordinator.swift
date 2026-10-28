#if !APP_STORE
import UIKit
import DeltaCore
import MelonDSDeltaCore

@MainActor
final class DuoCoverCoordinator {
    var onLidChanged: ((Bool) -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    private weak var controller: GameViewController?
    private var previousHingeStatus: Int?
    private var cover: UIView?

    var isVisible: Bool { cover != nil }

    var orientationLock: UIInterfaceOrientationMask? {
        guard isVisible, let orientation = controller?.view.window?.windowScene?.interfaceOrientation,
              orientation != .unknown else { return nil }
        return UIInterfaceOrientationMask(rawValue: 1 << orientation.rawValue)
    }

    init(controller: GameViewController) {
        self.controller = controller
    }

    func install() {
        guard #available(iOS 27.1, *), let controller else { return }
        controller.view.addInteraction(UIHingeInteraction { [weak self] _, update in
            guard let status = update.hinge?.status, status != .unknown else { return }
            self?.hingeChanged(to: status)
        })
    }

    func appeared() {
        guard #available(iOS 27.1, *), previousHingeStatus == nil, let controller else { return }
        // A session opened on the outer display starts with usable controls.
        previousHingeStatus = controller.traitCollection.horizontalSizeClass == .compact
            ? UIHinge.Status.closed.rawValue : UIHinge.Status.partiallyOpen.rawValue
    }

    func layout() {
        guard let cover, let controller, let scene = controller.view.window?.windowScene else { return }
        let angle: CGFloat
        switch scene.interfaceOrientation {
        case .portrait: angle = -.pi / 2
        case .portraitUpsideDown: angle = .pi / 2
        case .landscapeRight: angle = .pi
        default: angle = 0
        }
        cover.transform = CGAffineTransform(rotationAngle: angle)
        cover.frame = controller.view.bounds
        controller.view.bringSubviewToFront(cover)
    }

    @available(iOS 27.1, *)
    private func hingeChanged(to status: UIHinge.Status) {
        guard controller?.game != nil, previousHingeStatus != status.rawValue else { return }
        previousHingeStatus = status.rawValue
        if status == .closed {
            onLidChanged?(true)
            presentCover()
        } else {
            dismissCover()
        }
    }

    @available(iOS 27.1, *)
    private func presentCover() {
        guard cover == nil, let controller, let game = controller.game else { return }
        let traits = ControllerSkin.Traits(device: .iphone, displayType: .cover, orientation: .landscape)
        let candidates: [(any ControllerSkinProtocol)?] = [
            controller.controllerView?.controllerSkin,
            ControllerSkin.standardControllerSkin(for: game.type)
        ]
        guard let skin = candidates.compactMap({ $0 }).first(where: { $0.supports(traits) }) else { return }
        let view = DuoCoverView(controllerSkin: skin)
        view.onDismiss = { [weak self] in self?.dismissCover() }
        cover = view
        controller.view.addSubview(view)
        layout()
        view.showCover(animated: false)
        updateOrientationLock()
        onVisibilityChanged?(true)
    }

    private func dismissCover() {
        onLidChanged?(false)
        guard let cover else { return }
        cover.removeFromSuperview()
        self.cover = nil
        updateOrientationLock()
        onVisibilityChanged?(false)
    }

    private func updateOrientationLock() {
        controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
        controller?.parent?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

@MainActor
final class DuoEmulationCoordinator {
    typealias Cancel = @MainActor () -> Void
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Cancel

    private let isDS: Bool
    private let isSessionRunning: () -> Bool
    private let isCoreRunning: () -> Bool
    private let sendLidInput: (Bool) -> Void
    private let setCoverPaused: (Bool) -> Void
    private let schedule: Scheduler
    private var cancelPendingPause: Cancel?
    private var generation = 0
    private var isCovered = false
    private var isLidClosed = false
    private var isStopped = false

    init(gameType: GameType, isSessionRunning: @escaping () -> Bool,
         isCoreRunning: @escaping () -> Bool, sendLidInput: @escaping (Bool) -> Void,
         setCoverPaused: @escaping (Bool) -> Void,
         schedule: @escaping Scheduler = DuoEmulationCoordinator.schedulePause) {
        isDS = gameType == .ds
        self.isSessionRunning = isSessionRunning
        self.isCoreRunning = isCoreRunning
        self.sendLidInput = sendLidInput
        self.setCoverPaused = setCoverPaused
        self.schedule = schedule
    }

    func setLidClosed(_ closed: Bool) {
        guard !isStopped, isLidClosed != closed else { return }
        isLidClosed = closed
        applyLidState()
    }

    func applyLidState() {
        guard !isStopped, isDS else { return }
        sendLidInput(isLidClosed)
    }

    func setCovered(_ covered: Bool) {
        guard !isStopped, isCovered != covered else { return }
        isCovered = covered
        cancelPause()
        guard covered, isDS, isCoreRunning() else {
            setCoverPaused(covered)
            return
        }
        // Let the DS observe its lid input before emulation is paused.
        let pendingGeneration = generation
        cancelPendingPause = schedule(1) { [weak self] in
            guard let self, !self.isStopped, self.isCovered,
                  self.generation == pendingGeneration, self.isSessionRunning() else { return }
            self.cancelPendingPause = nil
            self.setCoverPaused(true)
        }
    }

    func stop() {
        guard !isStopped else { return }
        cancelPause()
        isStopped = true
        isCovered = false
        isLidClosed = false
        if isDS { sendLidInput(false) }
    }

    private func cancelPause() {
        generation += 1
        cancelPendingPause?()
        cancelPendingPause = nil
    }

    private static func schedulePause(after delay: TimeInterval,
                                      action: @escaping @MainActor () -> Void) -> Cancel {
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }
}
#endif
