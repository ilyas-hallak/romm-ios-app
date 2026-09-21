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

    /// Whether the phone should hide its own game picture and show just the
    /// touch controls.
    ///
    /// Only makes sense once the TV already carries the game and the touch
    /// controls are actually on screen. When they are hidden instead, a
    /// physical controller is in use and `shouldAutoDimPhone` already owns
    /// blanking the phone, so there is nothing left here for this to hide.
    static func shouldHidePhoneVideo(
        isRenderingExternally: Bool,
        isPhoneControllerOnlyEnabled: Bool,
        areTouchControlsHidden: Bool
    ) -> Bool {
        isRenderingExternally && isPhoneControllerOnlyEnabled && !areTouchControlsHidden
    }

    /// One flag per game view, saying whether that view may be hidden while the
    /// phone acts as a controller. A touch screen never may: on the DS the lower
    /// screen is what the player taps on, hiding it would mean tapping blind.
    ///
    /// - Parameter isTouchScreen: The skin's answer per screen, or nil while the
    ///   skin or its traits are not known yet, which is the case until the first
    ///   layout pass.
    static func touchScreenFlags(isTouchScreen: [Bool]?, gameViewCount: Int) -> [Bool] {
        guard let isTouchScreen else {
            // Nothing is known about the screens, so assume the worst and keep
            // every view, rather than hide the one the player taps on.
            return [Bool](repeating: true, count: gameViewCount)
        }
        guard isTouchScreen.count == gameViewCount else {
            // DeltaCore collapses the screens into one in a few cases the raw
            // skin does not report, so the order no longer maps. Rather than
            // guess, keep every view of a system that has a touch screen at all.
            return [Bool](repeating: isTouchScreen.contains(true), count: gameViewCount)
        }
        return isTouchScreen
    }
}
