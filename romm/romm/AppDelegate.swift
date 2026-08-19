//
//  AppDelegate.swift
//  romm
//
//  Created by Codex on 15.02.26.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppBootstrap.run()
        // A previous run may have been killed while the screen was blanked for
        // TV play, which would leave the panel dark at brightness 0.
        PhoneScreenBlanker.recoverIfNeeded()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationLock.currentMask
    }

    /// Claims the external-display scene so a running game can be shown on a TV
    /// directly instead of mirroring the phone. Every other role is left to
    /// SwiftUI, which owns the app's own window.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(name: "External Display", sessionRole: connectingSceneSession.role)
            config.delegateClass = ExternalDisplaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    // Handle URL callbacks (client token pairing)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        Logger.auth.info("App received URL: \(url.absoluteString)")

        guard url.scheme == "romm" else {
            Logger.auth.warning("Unknown URL scheme: \(url.scheme ?? "none")")
            return false
        }

        switch url.host {
        case "pair":
            Logger.auth.info("Pairing deep link received")
            let service = ClientTokenAuthService()
            if let code = service.handleDeepLink(url: url) {
                NotificationCenter.default.post(
                    name: .clientTokenPairingCode,
                    object: nil,
                    userInfo: ["code": code]
                )
            }
            return true

        default:
            Logger.auth.warning("Unknown URL host: \(url.host ?? "none")")
            return false
        }
    }
}

extension Notification.Name {
    static let clientTokenPairingCode = Notification.Name("clientTokenPairingCode")
}
