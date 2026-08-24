import Foundation

final class UserDefaultsUpdateCheckStateStore: PUpdateCheckStateStore {

    private let lastCheckKey = "lastUpdateCheckAt"
    private let dismissedBuildKey = "dismissedUpdateBuild"
    private let cachedBuildKey = "cachedRemoteBuild"
    private let forceCheckKey = "forceUpdateCheck"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var lastCheckedAt: Date? {
        get {
            guard let stamp = userDefaults.object(forKey: lastCheckKey) as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: stamp)
        }
        set {
            userDefaults.set(newValue?.timeIntervalSince1970, forKey: lastCheckKey)
        }
    }

    var dismissedBuild: Int? {
        get { positiveValue(forKey: dismissedBuildKey) }
        set { userDefaults.set(newValue ?? 0, forKey: dismissedBuildKey) }
    }

    var cachedPublishedBuild: Int? {
        get { positiveValue(forKey: cachedBuildKey) }
        set { userDefaults.set(newValue ?? 0, forKey: cachedBuildKey) }
    }

    var forcesCheck: Bool {
        userDefaults.bool(forKey: forceCheckKey)
    }

    // MARK: - Private

    /// Build numbers start at 1, so 0 from an absent key means "not set".
    private func positiveValue(forKey key: String) -> Int? {
        let stored = userDefaults.integer(forKey: key)
        return stored > 0 ? stored : nil
    }
}
