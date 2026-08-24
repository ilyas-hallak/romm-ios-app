import Foundation

/// Persists handed-off ROM ids as one id list per target, which keeps `forget`
/// cheap and avoids scattering a key per ROM across UserDefaults.
final class UserDefaultsExternalEmulatorHandoffStore: PExternalEmulatorHandoffStore {

    private let keyPrefix = "externalEmulator.handoff."
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasHandedOff(romId: Int, to target: ExternalEmulator) -> Bool {
        romIds(for: target).contains(romId)
    }

    func markHandedOff(romId: Int, to target: ExternalEmulator) {
        var ids = romIds(for: target)
        guard ids.insert(romId).inserted else { return }
        userDefaults.set(Array(ids), forKey: key(for: target))
    }

    func forget(romId: Int) {
        for target in ExternalEmulator.allCases {
            var ids = romIds(for: target)
            guard ids.remove(romId) != nil else { continue }
            userDefaults.set(Array(ids), forKey: key(for: target))
        }
    }

    // MARK: - Private

    private func key(for target: ExternalEmulator) -> String {
        keyPrefix + target.rawValue
    }

    private func romIds(for target: ExternalEmulator) -> Set<Int> {
        Set(userDefaults.array(forKey: key(for: target)) as? [Int] ?? [])
    }
}
