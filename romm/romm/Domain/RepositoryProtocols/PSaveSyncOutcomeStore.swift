import Foundation

/// The last completed sync run as a whole. Split from ``PCloudSaveSyncStore``,
/// which keeps the per-ROM metadata, so a consumer that only wants to know how
/// syncing went overall does not depend on the per-ROM surface.
protocol PSaveSyncOutcomeStore: AnyObject {
    func recordRun(_ outcome: SaveSyncOutcome)
    /// Nil when no run has finished on this device yet, which is not the same
    /// as a run that found nothing to do.
    func lastRun() -> SaveSyncOutcome?
}
