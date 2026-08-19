import Foundation

/// The two decisions behind Play on TV, as plain functions over plain values.
///
/// They used to sit inside a `UIWindow` owning class and, copied verbatim, in two
/// SwiftUI views. Both are statements about a handful of booleans, which is
/// exactly the part worth testing, and it was the one part that could only be
/// checked by holding a controller in front of an actual television.
enum ExternalDisplayPolicy {

    /// Whether the app should paint the attached display itself.
    ///
    /// Outside a running game the answer is no on purpose: mirroring the library
    /// UI is the sensible thing for a browsing user, and it is also what a viewer
    /// expects when nothing is being played.
    static func shouldRenderExternally(
        isDisplayConnected: Bool,
        isSessionRunning: Bool,
        isPlayOnTVEnabled: Bool
    ) -> Bool {
        isDisplayConnected && isSessionRunning && isPlayOnTVEnabled
    }

    /// Whether the phone may dim itself.
    ///
    /// Hidden touch controls are the app's signal that a physical controller is
    /// in use, so together with the game being on the TV it means nobody is
    /// looking at the handset. An open menu is the counter case: it is operated by
    /// touch, so dimming underneath it would be absurd.
    static func shouldAutoDimPhone(
        isRenderingExternally: Bool,
        areTouchControlsHidden: Bool,
        isMenuOpen: Bool,
        isAutoDimPhoneEnabled: Bool
    ) -> Bool {
        isAutoDimPhoneEnabled && isRenderingExternally && areTouchControlsHidden && !isMenuOpen
    }
}
