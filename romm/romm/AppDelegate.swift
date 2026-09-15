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
        PhoneScreenBlanker.shared.recoverIfNeeded()
        // Downloads keep transferring while the app is gone, so the queue has to
        // be reconciled with what the session actually still holds. This also
        // runs when the app was only relaunched to be handed session events,
        // which is exactly when the queue would otherwise be empty.
        Task { @MainActor in
            await DownloadQueueManager.shared.resumeInterruptedJobs()
        }
        return true
    }

    /// The system relaunches the app in the background purely to deliver the
    /// events of a background session, and faults it if the handler is not
    /// called once they have all been dealt with.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Isolation is assumed rather than hopped to, because the handler has to
        // be taken before this method returns. UIKit calls it on the main thread.
        MainActor.assumeIsolated {
            let queue = DownloadQueueManager.shared
            guard queue.handlesBackgroundSession(identifier: identifier) else {
                // Not a session of ours, so nothing here is waiting on it.
                Logger.data.warning("Background session events for unknown identifier: \(identifier)")
                completionHandler()
                return
            }
            queue.handleBackgroundSessionEvents(completionHandler: completionHandler)
        }
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
