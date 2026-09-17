import Foundation

/// Whether the automatic cloud save/state sync is turned on. Split from
/// `PCloudSaveSyncStore` (which persists per-ROM sync metadata) so a
/// consumer that only needs the on/off switch, like `CloudSaveSyncService`,
/// can depend on just that instead of the whole settings surface.
protocol PCloudSaveSyncSettings: AnyObject {
    var isEnabled: Bool { get }
}
