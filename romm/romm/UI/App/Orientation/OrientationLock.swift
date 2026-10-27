//
//  OrientationLock.swift
//  romm
//
//  Created by Codex on 15.02.26.
//

import UIKit

enum OrientationLock {
    private(set) static var currentMask: UIInterfaceOrientationMask = .portrait

    static func set(_ mask: UIInterfaceOrientationMask) {
        set(mask, rotateTo: nil)
    }

    static func set(_ mask: UIInterfaceOrientationMask, rotateTo: UIInterfaceOrientation?) {
        if Thread.isMainThread {
            apply(mask, rotateTo: rotateTo)
        } else {
            DispatchQueue.main.async {
                apply(mask, rotateTo: rotateTo)
            }
        }
    }

    private static func apply(_ mask: UIInterfaceOrientationMask, rotateTo: UIInterfaceOrientation?)
    {
        if currentMask == mask, rotateTo == nil {
            print("🔒 OrientationLock unchanged (\(mask.rawValue)) - skipping update")
            return
        }

        if let rotateTo {
            print(
                "🔒 OrientationLock set to \(mask.rawValue) with forced orientation \(rotateTo.rawValue)"
            )
        } else {
            print("🔒 OrientationLock set allowed orientations to \(mask.rawValue)")
        }

        currentMask = mask

        guard let windowScene = activeWindowScene else {
            print("⚠️ OrientationLock: no active window scene found")
            return
        }

        let rootViewController =
            keyWindow(in: windowScene)?.rootViewController
            ?? windowScene.windows.first?.rootViewController
        let topViewController = rootViewController?.topMostPresentedViewController()

        rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        topViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        if #available(iOS 16.0, *) {
            let requestedMask: UIInterfaceOrientationMask
            if let rotateTo {
                let forcedMask = orientationMask(for: rotateTo)
                requestedMask = mask.intersection(forcedMask).isEmpty ? mask : forcedMask
            } else {
                requestedMask = mask
            }

            let preferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: requestedMask
            )

            windowScene.requestGeometryUpdate(preferences) { error in
                print("⚠️ Failed to update orientation: \(error.localizedDescription)")
            }
        }

        UIViewController.attemptRotationToDeviceOrientation()
    }

    /// How the phone is held right now, so a caller can skip forcing a side the
    /// device is already on.
    static var currentOrientation: UIInterfaceOrientation? {
        activeWindowScene?.interfaceOrientation
    }

    private static var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
    }

    private static func keyWindow(in scene: UIWindowScene) -> UIWindow? {
        scene.windows.first(where: \.isKeyWindow)
    }

    private static func orientationMask(
        for orientation: UIInterfaceOrientation
    ) -> UIInterfaceOrientationMask {
        switch orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return currentMask
        }
    }
}

private extension UIViewController {
    func topMostPresentedViewController() -> UIViewController {
        var top = self
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
