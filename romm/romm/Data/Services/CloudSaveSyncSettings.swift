import Foundation

final class CloudSaveSyncSettings: ObservableObject {
    static let shared = CloudSaveSyncSettings()

    private let userDefaults = UserDefaults.standard
    private enum Keys {
        static let enabled = "cloud_save_sync_enabled"
    }

    @Published var isEnabled: Bool {
        didSet { userDefaults.set(isEnabled, forKey: Keys.enabled) }
    }

    private init() {
        self.isEnabled = userDefaults.bool(forKey: Keys.enabled)
    }
}
