import Foundation

protocol PExternalDisplayPreference: AnyObject {
    /// Draw the game on an attached display ourselves instead of letting the
    /// system mirror the whole phone.
    var isPlayOnTVEnabled: Bool { get set }

    /// Let the handset go dark on its own once the game is on the TV and a
    /// controller is in use.
    var isAutoDimPhoneEnabled: Bool { get set }

    /// Brightness captured before the phone screen was blanked. Not a setting the
    /// user makes, but it has to outlive the process: brightness is system wide,
    /// so a crash while blanked would otherwise leave a phone that looks broken.
    /// `nil` means nothing is pending recovery.
    var blankedPhoneBrightness: Double? { get set }
}
