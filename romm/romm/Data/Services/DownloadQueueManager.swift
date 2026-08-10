import Foundation
import Observation

/// A single ROM download tracked by the queue.
struct DownloadTask: Identifiable {
    /// The ROM id — also used to de-duplicate (one active download per ROM).
    let id: Int
    let rom: Rom
    let name: String
    let platformSlug: String?
    var status: Status

    enum Status: Equatable {
        case queued
        case downloading(progress: Double?) // 0...1, or nil when size is unknown
        case finished
        case failed(String)
    }

    var isActive: Bool {
        switch status {
        case .queued, .downloading: return true
        case .finished, .failed: return false
        }
    }
}

/// Serial, in-memory download queue shared across the app. Views observe it to
/// show live progress; the ROM detail screen enqueues into it and can be left
/// while downloads keep running. Finished ROMs land in the normal downloaded
/// list, so the queue itself is not persisted across launches.
@Observable
@MainActor
final class DownloadQueueManager {
    static let shared = DownloadQueueManager()

    private(set) var tasks: [DownloadTask] = []

    private let apiClient: PRommAPIClient
    private var isProcessing = false
    private let logger = Logger.viewModel

    init(apiClient: PRommAPIClient = RommAPIClient.shared) {
        self.apiClient = apiClient
    }

    // MARK: - Derived state

    /// Number of downloads still queued or in progress.
    var activeCount: Int {
        tasks.filter { $0.isActive }.count
    }

    /// Count of finished downloads — used by the Downloads tab to refresh its list.
    var finishedCount: Int {
        tasks.filter { if case .finished = $0.status { return true } else { return false } }.count
    }

    func status(forRomId id: Int) -> DownloadTask.Status? {
        tasks.first { $0.id == id }?.status
    }

    // MARK: - Queue operations

    /// Adds a ROM to the queue. No-op if it is already queued, downloading or
    /// finished. A previously failed task is re-queued.
    func enqueue(rom: Rom) {
        if let index = tasks.firstIndex(where: { $0.id == rom.id }) {
            switch tasks[index].status {
            case .queued, .downloading, .finished:
                return
            case .failed:
                tasks[index].status = .queued
            }
        } else {
            tasks.append(DownloadTask(
                id: rom.id,
                rom: rom,
                name: rom.name,
                platformSlug: rom.platformSlug,
                status: .queued
            ))
        }
        startProcessingIfNeeded()
    }

    /// Removes a queued, finished or failed task. In-progress downloads are not
    /// cancellable in this version (the underlying service has no cancel hook).
    func remove(id: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if case .downloading = tasks[index].status { return }
        tasks.remove(at: index)
    }

    func retry(id: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if case .failed = tasks[index].status {
            tasks[index].status = .queued
            startProcessingIfNeeded()
        }
    }

    /// Clears finished and failed tasks from the list.
    func clearCompleted() {
        tasks.removeAll { !$0.isActive }
    }

    // MARK: - Processing

    private func startProcessingIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { await processQueue() }
    }

    private func processQueue() async {
        defer { isProcessing = false }
        while let index = tasks.firstIndex(where: { if case .queued = $0.status { return true } else { return false } }) {
            let task = tasks[index]
            tasks[index].status = .downloading(progress: nil)
            do {
                try await download(task)
                updateStatus(id: task.id, to: .finished)
                logger.info("Queue: finished download for ROM \(task.id) - \(task.name)")
            } catch {
                updateStatus(id: task.id, to: .failed(error.localizedDescription))
                logger.error("Queue: download failed for ROM \(task.id): \(error)")
            }
        }
    }

    private func updateStatus(id: Int, to status: DownloadTask.Status) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        // A late progress callback (dispatched async onto the main actor) can
        // arrive after the download already finished — don't let it clobber a
        // terminal state back into `.downloading`, or the spinner never stops.
        if case .downloading = status {
            switch tasks[index].status {
            case .finished, .failed: return
            default: break
            }
        }
        tasks[index].status = status
    }

    private func download(_ task: DownloadTask) async throws {
        let rom = task.rom
        // Resolve the concrete files to download from the server details.
        let details = try await apiClient.getRomDetails(id: rom.id)
        var files: [RomFileInfo] = []
        if !details.fsName.isEmpty {
            files.append(RomFileInfo(
                id: details.fsName,
                fileName: details.fsName,
                fileSizeBytes: Int64(details.fsSizeBytes),
                fileExtension: (details.fsName as NSString).pathExtension
            ))
        }
        for supplementary in details.files
        where supplementary.fileName != details.fsName && !supplementary.fileName.isEmpty {
            files.append(RomFileInfo(from: supplementary))
        }
        if files.isEmpty {
            let fallbackName = rom.fileName ?? "\(rom.name).rom"
            files = [RomFileInfo(
                id: fallbackName,
                fileName: fallbackName,
                fileSizeBytes: Int64(rom.sizeBytes ?? 0),
                fileExtension: (fallbackName as NSString).pathExtension
            )]
        }

        let downloadService = LocalROMDownloadService(apiClient: apiClient)
        _ = try await downloadService.downloadROM(rom: rom, files: files) { [weak self] downloaded, total in
            guard let self else { return }
            let progress: Double? = total > 0
                ? min(max(Double(downloaded) / Double(total), 0), 1)
                : nil
            Task { @MainActor in
                self.updateStatus(id: rom.id, to: .downloading(progress: progress))
            }
        }
    }
}
