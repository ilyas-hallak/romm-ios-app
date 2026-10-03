import Foundation

/// Persists handed-off ROM ids as one id list per target, which keeps `forget`
/// cheap and avoids scattering a key per ROM across UserDefaults.
final class UserDefaultsExternalEmulatorHandoffStore: PExternalEmulatorHandoffStore {

    private let keyPrefix = "externalEmulator.handoff."
    /// Deliberately a second key rather than a richer value under the first one,
    /// so installations from before the identifier cache keep their handoff state.
    private let identifierKeyPrefix = "externalEmulator.gameIdentifier."
    private let pasteboardCopyKeyPrefix = "externalEmulator.pasteboardCopy."
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func hasHandedOff(romId: Int, to target: ExternalEmulatorID) -> Bool {
        romIds(forKey: key(for: target)).contains(romId)
    }

    func markHandedOff(romId: Int, to target: ExternalEmulatorID) {
        insert(romId: romId, intoKey: key(for: target))
    }

    func forget(romId: Int) {
        for target in ExternalEmulatorID.allCases {
            remove(romId: romId, fromKey: key(for: target))
            remove(romId: romId, fromKey: pasteboardCopyKey(for: target))
        }
        // The ROM may have been replaced by a different dump under the same id,
        // so a cached content hash is no longer trustworthy either.
        for kind in ExternalGameIdentifierKind.allCases {
            var identifiers = gameIdentifiers(for: kind)
            guard identifiers.removeValue(forKey: String(romId)) != nil else { continue }
            userDefaults.set(identifiers, forKey: identifierKey(for: kind))
        }
    }

    func hasCopiedToPasteboard(romId: Int, to target: ExternalEmulatorID) -> Bool {
        romIds(forKey: pasteboardCopyKey(for: target)).contains(romId)
    }

    func markCopiedToPasteboard(romId: Int, to target: ExternalEmulatorID) {
        insert(romId: romId, intoKey: pasteboardCopyKey(for: target))
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

    private func pasteboardCopyKey(for target: ExternalEmulatorID) -> String {
        pasteboardCopyKeyPrefix + target.rawValue
    }

    private func identifierKey(for kind: ExternalGameIdentifierKind) -> String {
        identifierKeyPrefix + kind.rawValue
    }

    private func gameIdentifiers(for kind: ExternalGameIdentifierKind) -> [String: String] {
        userDefaults.dictionary(forKey: identifierKey(for: kind)) as? [String: String] ?? [:]
    }

    private func romIds(forKey key: String) -> Set<Int> {
        Set(userDefaults.array(forKey: key) as? [Int] ?? [])
    }

    private func insert(romId: Int, intoKey key: String) {
        var ids = romIds(forKey: key)
        guard ids.insert(romId).inserted else { return }
        userDefaults.set(Array(ids), forKey: key)
    }

    private func remove(romId: Int, fromKey key: String) {
        var ids = romIds(forKey: key)
        guard ids.remove(romId) != nil else { return }
        userDefaults.set(Array(ids), forKey: key)
    }
}
