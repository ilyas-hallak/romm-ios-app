import Foundation

/// What a Play tap should do next for a ROM and its configured external target.
enum ExternalPlayAction: Equatable {
    /// Already handed off, or the user said it already is, deep link straight in.
    case launchDirectly
    /// Went to this target's pasteboard once already, with no confirmed import
    /// since. Ask before deep linking, since a paste could still be pending.
    case confirmBeforeRelaunching
    /// Nothing known about this ROM and target yet, hand it over.
    case handOver
}

/// Works out `ExternalPlayAction` from what the handoff store already knows,
/// kept free of `ExternalPlayCoordinator`'s UIKit dependencies so it tests
/// on its own.
enum ExternalPlayDecision {
    static func action(
        romId: Int,
        target: ExternalEmulatorID,
        delivery: ExternalROMDelivery,
        handoffStore: PExternalEmulatorHandoffStore
    ) -> ExternalPlayAction {
        if handoffStore.hasHandedOff(romId: romId, to: target) {
            return .launchDirectly
        }
        if delivery == .pasteboard, handoffStore.hasCopiedToPasteboard(romId: romId, to: target) {
            return .confirmBeforeRelaunching
        }
        return .handOver
    }
}
