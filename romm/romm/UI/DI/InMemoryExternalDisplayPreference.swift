import Foundation

final class InMemoryExternalDisplayPreference: PExternalDisplayPreference {
    var isPlayOnTVEnabled: Bool = true
    var isAutoDimPhoneEnabled: Bool = true
    var isPhoneControllerOnlyEnabled: Bool = false
    var blankedPhoneBrightness: Double?
}
