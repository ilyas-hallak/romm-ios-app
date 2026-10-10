import Foundation

/// Applies one battery save download: fetch it, trim its GBA RTC footer,
/// write it into place when the caller's own freshness rules allow it, then
/// confirm the download with the server regardless, so a declined write
/// still stops the server replanning it.
///
/// Shared by `SaveSyncRunner`, `CloudSaveSyncService` (its negotiated and
/// legacy pulls) and `BatteryConflictResolver`, which otherwise ran this same
/// sequence with small, easy-to-miss differences (see issue #212). Each
/// caller still owns its own freshness check, error handling and logging;
/// this only carries out the steps once a caller has decided to.
///
/// Not a UseCase: it composes several of them, and a UseCase may not call
/// another one. Lives at the same Session/UI-sync layer as its callers.
@MainActor
final class BatteryDownloadChain {
    /// What `apply` actually did with the downloaded bytes.
    struct Result {
        let data: Data
        let wrote: Bool
    }

    private let logger = Logger.sync
    private let saveStore: PSaveStore
    private let downloadSaveUseCase: PDownloadSaveUseCase
    private let confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase

    init(
        saveStore: PSaveStore,
        downloadSaveUseCase: PDownloadSaveUseCase,
        confirmSaveDownloadUseCase: PConfirmSaveDownloadUseCase
    ) {
        self.saveStore = saveStore
        self.downloadSaveUseCase = downloadSaveUseCase
        self.confirmSaveDownloadUseCase = confirmSaveDownloadUseCase
    }

    /// Downloads `saveId`, trims it, and asks `shouldWrite` whether the
    /// trimmed bytes should replace `romId`'s battery file (e.g. a blank
    /// candidate never may, see `BatteryDownloadDecision`). The download is
    /// confirmed either way; confirming is best effort, a failure there is
    /// only logged.
    func apply(
        romId: Int,
        saveId: Int,
        deviceId: String?,
        serverUpdatedAt: Date?,
        platformSlug: String?,
        shouldWrite: (Data) -> Bool
    ) async throws -> Result {
        let data = try await downloadSaveUseCase.execute(id: saveId, deviceId: deviceId, sessionId: nil)
        let trimmed = GBABatteryFooter.trimmingRTCFooter(from: data, platformSlug: platformSlug)
        let wrote = shouldWrite(trimmed)
        if wrote {
            try saveStore.writeBattery(romId: romId, data: trimmed)
            // Preserve server mtime so subsequent local-vs-server compares are
            // not skewed by device clock drift after the write-to-disk timestamp.
            if let serverUpdatedAt {
                try? saveStore.setBatteryModifiedAt(romId: romId, date: serverUpdatedAt)
            }
        }
        await confirmDownload(saveId: saveId, deviceId: deviceId)
        return Result(data: trimmed, wrote: wrote)
    }

    private func confirmDownload(saveId: Int, deviceId: String?) async {
        guard let deviceId else { return }
        do {
            _ = try await confirmSaveDownloadUseCase.execute(id: saveId, deviceId: deviceId)
        } catch {
            logger.warning("Download confirmation failed (save \(saveId)): \(error.localizedDescription)")
        }
    }
}
