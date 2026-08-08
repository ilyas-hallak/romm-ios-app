import Foundation

/// Lightweight UserDefaults-backed preferences for on-screen controller haptics.
/// Kept as a simple value store (not part of the DI graph) because the touch
/// controller is a plain UIView instantiated outside the dependency factory.
enum HapticsPreferences {
    private static let onReleaseKey = "haptics.onRelease"

    private static let defaults = UserDefaults.standard

    /// Whether a haptic should fire when a finger lifts off an on-screen button.
    /// Defaults to on to mirror the press haptic (like Ignited).
    static var onRelease: Bool {
        get {
            if defaults.object(forKey: onReleaseKey) == nil { return true }
            return defaults.bool(forKey: onReleaseKey)
        }
        set {
            defaults.set(newValue, forKey: onReleaseKey)
        }
    }
}
