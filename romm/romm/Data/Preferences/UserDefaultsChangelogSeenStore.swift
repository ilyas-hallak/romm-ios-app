import Foundation

final class UserDefaultsChangelogSeenStore: PChangelogSeenStore {

    private let key = "lastSeenChangelogBuild"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var lastSeenBuild: Int? {
        get {
            // `integer(forKey:)` returns 0 for an absent key, which means "never seen".
            let stored = userDefaults.integer(forKey: key)
            return stored > 0 ? stored : nil
        }
        set {
            userDefaults.set(newValue ?? 0, forKey: key)
        }
    }
}
