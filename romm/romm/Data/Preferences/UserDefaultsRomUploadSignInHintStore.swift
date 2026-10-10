import Foundation

final class UserDefaultsRomUploadSignInHintStore: PRomUploadSignInHintStore {

    private let key = "romUpload.missingScopeHintShown"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasShownMissingScopeHint: Bool {
        userDefaults.bool(forKey: key)
    }

    func markMissingScopeHintShown() {
        userDefaults.set(true, forKey: key)
    }
}
