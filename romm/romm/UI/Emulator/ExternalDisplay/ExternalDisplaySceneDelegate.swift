import UIKit

/// Scene delegate for the `windowExternalDisplayNonInteractive` role. The app
/// itself runs on the SwiftUI lifecycle, so this handles the one scene role
/// SwiftUI does not model, and forwards it to `ExternalDisplayManager`.
///
/// iOS only offers this scene when the app declares the role in its
/// `UIApplicationSceneManifest` (see Info.plist) and `AppDelegate` returns a
/// configuration naming this class.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated {
            ExternalDisplayManager.shared.sceneDidConnect(windowScene)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated {
            ExternalDisplayManager.shared.sceneDidDisconnect(windowScene)
        }
    }
}
