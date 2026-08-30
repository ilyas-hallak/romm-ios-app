import Foundation

/// How hard the rumble feedback is driven. Three steps instead of a slider: the
/// difference between them is easy to feel, while a percentage only invites
/// fiddling.
enum RumbleIntensity: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Factor the motor strength reported by the core is multiplied with before
    /// it reaches the controller or the device haptics.
    var scale: Float {
        switch self {
        case .low: return 0.45
        case .medium: return 0.7
        case .high: return 1.0
        }
    }
}

/// User preference for rumble feedback. Off by default so an existing library
/// keeps behaving the way it always has until the user asks for it.
protocol PRumblePreference: AnyObject {
    var isEnabled: Bool { get set }
    var intensity: RumbleIntensity { get set }
}
