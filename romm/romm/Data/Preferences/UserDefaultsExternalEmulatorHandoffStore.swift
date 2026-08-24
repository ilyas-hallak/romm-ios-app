import Foundation

/// Persists handed-off ROM ids as one id list per target, which keeps `forget`
/// cheap and avoids scattering a key per ROM across UserDefaults.
final class UserDefaultsExternalEmulatorHandoffStore: PExternalEmulatorHandoffStore {

    private let keyPrefix = "externalEmulator.handoff."
    /// Deliberately a second key rather than a richer value under the first one,
    /// so installations from before the identifier cache keep their handoff state.
    private let identifierKeyPrefix = "externalEmulator.gameIdentifier."
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasHandedOff(romId: Int, to target: ExternalEmulatorID) -> Bool {
        romIds(for: target).contains(romId)
    }

    func markHandedOff(romId: Int, to target: ExternalEmulatorID) {
        var ids = romIds(for: target)
        guard ids.insert(romId).inserted else { return }
        userDefaults.set(Array(ids), forKey: key(for: target))
    }

    func forget(romId: Int) {
        for target in ExternalEmulatorID.allCases {
            var ids = romIds(for: target)
            guard ids.remove(romId) != nil else { continue }
            userDefaults.set(Array(ids), forKey: key(for: target))
        }
        // The ROM may have been replaced by a different dump under the same id,
        // so a cached content hash is no longer trustworthy either.
        for kind in ExternalGameIdentifierKind.allCases {
            var identifiers = gameIdentifiers(for: kind)
            guard identifiers.removeValue(forKey: String(romId)) != nil else { continue }
            userDefaults.set(identifiers, forKey: identifierKey(for: kind))
        }
    }

    func cachedGameIdentifier(romId: Int, kind: ExternalGameIdentifierKind) -> String? {
        gameIdentifiers(for: kind)[String(romId)]
    }

    func cacheGameIdentifier(_ identifier: String, romId: Int, kind: ExternalGameIdentifierKind) {
        // A file name is free to work out again, caching it would only add a way
        // for it to go stale.
        guard kind != .fileName else { return }
        var identifiers = gameIdentifiers(for: kind)
        identifiers[String(romId)] = identifier
        userDefaults.set(identifiers, forKey: identifierKey(for: kind))
    }

    // MARK: - Private

    private func key(for target: ExternalEmulatorID) -> String {
        keyPrefix + target.rawValue
    }

    private func romIds(for target: ExternalEmulatorID) -> Set<Int> {
        Set(userDefaults.array(forKey: key(for: target)) as? [Int] ?? [])
    }

    private func identifierKey(for kind: ExternalGameIdentifierKind) -> String {
        identifierKeyPrefix + kind.rawValue
    }

    private func gameIdentifiers(for kind: ExternalGameIdentifierKind) -> [String: String] {
        userDefaults.dictionary(forKey: identifierKey(for: kind)) as? [String: String] ?? [:]
    }
}
