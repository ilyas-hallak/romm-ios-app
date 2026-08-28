import Foundation

final class UserDefaultsGamepadFaceButtonPreferenceStore: PGamepadFaceButtonPreference {
    private let key = "emulator.gamepad.swapFaceButtons"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var isSwapped: Bool {
        get { userDefaults.bool(forKey: key) }
        set { userDefaults.set(newValue, forKey: key) }
    }
}
