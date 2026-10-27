import Foundation

/// What this device holds locally, shown before logging out.
struct LocalDataSummary: Equatable {
    let downloadedROMCount: Int
    let downloadedBytes: Int64
    /// Games with a battery save or save state the server has not confirmed yet.
    let gamesWithUnsyncedSaves: Int

    var hasDownloads: Bool { downloadedROMCount > 0 }
}
