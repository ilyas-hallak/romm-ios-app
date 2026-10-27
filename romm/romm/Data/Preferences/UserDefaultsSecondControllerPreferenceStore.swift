import Foundation

final class UserDefaultsSecondControllerPreferenceStore: PSecondControllerPreference {
    private let acceptsRemotePadKey = "secondController.acceptsRemotePad"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var acceptsRemotePad: Bool {
        get { userDefaults.bool(forKey: acceptsRemotePadKey) }
        set { userDefaults.set(newValue, forKey: acceptsRemotePadKey) }
    }
}
