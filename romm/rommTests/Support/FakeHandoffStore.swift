import Foundation
@testable import romm

/// Stateful `PExternalEmulatorHandoffStore` double. Tracks handed-off and
/// pasteboard-copied rom ids per target-independent set, which is enough for
/// every test that uses it: none exercises two targets for the same ROM.
final class FakeHandoffStore: PExternalEmulatorHandoffStore, @unchecked Sendable {
    private(set) var handedOff: Set<Int> = []
    private(set) var pasteboardCopied: Set<Int> = []
    private(set) var forgottenRomIds: [Int] = []
    var identifiers: [Int: String] = [:]

    func hasHandedOff(romId: Int, to target: ExternalEmulatorID) -> Bool {
        handedOff.contains(romId)
    }

    func markHandedOff(romId: Int, to target: ExternalEmulatorID) {
        handedOff.insert(romId)
    }

    func forget(romId: Int) {
        handedOff.remove(romId)
        pasteboardCopied.remove(romId)
        forgottenRomIds.append(romId)
    }

    func hasCopiedToPasteboard(romId: Int, to target: ExternalEmulatorID) -> Bool {
        pasteboardCopied.contains(romId)
    }

    func markCopiedToPasteboard(romId: Int, to target: ExternalEmulatorID) {
        pasteboardCopied.insert(romId)
    }

    func cachedGameIdentifier(romId: Int, kind: ExternalGameIdentifierKind) -> String? {
        identifiers[romId]
    }

    func cacheGameIdentifier(_ identifier: String, romId: Int, kind: ExternalGameIdentifierKind) {
        identifiers[romId] = identifier
    }
}
