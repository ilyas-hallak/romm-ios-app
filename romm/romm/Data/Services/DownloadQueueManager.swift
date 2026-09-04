import Foundation
import Observation

/// Serial, in-memory download queue shared across the app. Views observe it to
/// show live progress; the ROM detail screen enqueues into it and can be left
/// while downloads keep running. Finished ROMs land in the normal downloaded
/// list, so the queue itself is not persisted across launches.
@Observable
@MainActor
final class DownloadQueueManager {
    static let shared = DownloadQueueManager()

    private(set) var tasks: [DownloadTask] = []

    private let downloadUseCase: PDownloadROMUseCase
    private var isProcessing = false
    private let logger = Logger.viewModel

    /// The shared queue is built from view context with no factory at hand, so an
    /// omitted use case falls back to the app's default client. Resolved in the
    /// body rather than as a default argument, because default arguments are
    /// evaluated outside this type's actor isolation.
    init(downloadUseCase: PDownloadROMUseCase? = nil) {
        self.downloadUseCase = downloadUseCase
            ?? DownloadROMUseCase(apiClient: DefaultDependencyFactory.shared.apiClient)
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
        _ = try await downloadUseCase.execute(rom: task.rom) { [weak self] downloaded, total in
            guard let self else { return }
            let progress: Double? = total > 0
                ? min(max(Double(downloaded) / Double(total), 0), 1)
                : nil
            Task { @MainActor in
                self.updateStatus(id: task.id, to: .downloading(progress: progress))
            }
        }
    }
}
